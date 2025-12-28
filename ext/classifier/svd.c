/*
 * svd.c
 * Jacobi SVD implementation for Classifier native linear algebra
 *
 * This is a port of the pure Ruby SVD implementation from
 * lib/classifier/extensions/vector.rb
 */

#include "linalg.h"

#define SVD_MAX_SWEEPS 20
#define SVD_CONVERGENCE_THRESHOLD 0.001

/* Helper: Create identity matrix */
static CMatrix *cmatrix_identity(size_t n)
{
    CMatrix *m = cmatrix_alloc(n, n);
    for (size_t i = 0; i < n; i++) {
        MAT_AT(m, i, i) = 1.0;
    }
    return m;
}

/* Helper: Clone a matrix */
static CMatrix *cmatrix_clone(CMatrix *m)
{
    CMatrix *result = cmatrix_alloc(m->rows, m->cols);
    memcpy(result->data, m->data, m->rows * m->cols * sizeof(double));
    return result;
}

/* Helper: Apply Jacobi rotation to matrix Q and accumulator V */
static void apply_jacobi_rotation(CMatrix *q, CMatrix *v, size_t p, size_t r,
                                   double cosine, double sine)
{
    size_t n = q->rows;

    /* Apply rotation to Q: Q = R^T * Q * R */
    /* First: Q = Q * R (affects columns p and r) */
    for (size_t i = 0; i < n; i++) {
        double qip = MAT_AT(q, i, p);
        double qir = MAT_AT(q, i, r);
        MAT_AT(q, i, p) = cosine * qip - sine * qir;
        MAT_AT(q, i, r) = sine * qip + cosine * qir;
    }

    /* Second: Q = R^T * Q (affects rows p and r) */
    for (size_t j = 0; j < n; j++) {
        double qpj = MAT_AT(q, p, j);
        double qrj = MAT_AT(q, r, j);
        MAT_AT(q, p, j) = cosine * qpj - sine * qrj;
        MAT_AT(q, r, j) = sine * qpj + cosine * qrj;
    }

    /* Accumulate rotation in V: V = V * R */
    for (size_t i = 0; i < v->rows; i++) {
        double vip = MAT_AT(v, i, p);
        double vir = MAT_AT(v, i, r);
        MAT_AT(v, i, p) = cosine * vip - sine * vir;
        MAT_AT(v, i, r) = sine * vip + cosine * vir;
    }
}

/*
 * Jacobi SVD decomposition
 *
 * Computes A = U * S * V^T where:
 * - U is m x m orthogonal
 * - S is m x n diagonal (returned as vector of singular values)
 * - V is n x n orthogonal
 *
 * Based on one-sided Jacobi algorithm from vector.rb
 */
void jacobi_svd(CMatrix *a, CMatrix **u_out, CMatrix **v_out, CVector **s_out)
{
    size_t m = a->rows;
    size_t n = a->cols;
    int transposed = 0;
    CMatrix *work_matrix;

    /* Ensure we work with a "tall" matrix for numerical stability */
    if (m >= n) {
        /* A^T * A */
        CMatrix *at = cmatrix_transpose(a);
        work_matrix = cmatrix_multiply(at, a);
        cmatrix_free(at);
    } else {
        /* A * A^T */
        CMatrix *at = cmatrix_transpose(a);
        work_matrix = cmatrix_multiply(a, at);
        cmatrix_free(at);
        transposed = 1;
    }

    size_t size = work_matrix->rows;  /* This is min(m, n) effectively */
    CMatrix *q = cmatrix_clone(work_matrix);
    CMatrix *v = cmatrix_identity(size);
    CMatrix *prev_q = NULL;

    /* Jacobi iteration */
    for (int sweep = 0; sweep < SVD_MAX_SWEEPS; sweep++) {
        /* Apply rotations to diagonalize Q */
        for (size_t p = 0; p < size - 1; p++) {
            for (size_t r = p + 1; r < size; r++) {
                double qpr = MAT_AT(q, p, r);
                double qpp = MAT_AT(q, p, p);
                double qrr = MAT_AT(q, r, r);

                /* Compute rotation angle */
                double numerator = 2.0 * qpr;
                double denominator = qpp - qrr;
                double angle;

                if (fabs(denominator) < CLASSIFIER_EPSILON) {
                    angle = (numerator >= 0) ? M_PI / 4.0 : -M_PI / 4.0;
                } else {
                    angle = atan(numerator / denominator) / 2.0;
                }

                double cosine = cos(angle);
                double sine = sin(angle);

                apply_jacobi_rotation(q, v, p, r, cosine, sine);
            }
        }

        /* Check for convergence */
        if (sweep == 0) {
            prev_q = cmatrix_clone(q);
        } else {
            double sum_diff = 0.0;
            for (size_t i = 0; i < size; i++) {
                double diff = fabs(MAT_AT(q, i, i) - MAT_AT(prev_q, i, i));
                if (diff > 0.001) {
                    sum_diff += diff;
                }
            }

            /* Update prev_q for next iteration */
            memcpy(prev_q->data, q->data, size * size * sizeof(double));

            if (sum_diff <= SVD_CONVERGENCE_THRESHOLD) {
                break;
            }
        }
    }

    if (prev_q) cmatrix_free(prev_q);

    /* Extract singular values (sqrt of diagonal elements of Q) */
    CVector *s = cvector_alloc(size);
    for (size_t i = 0; i < size; i++) {
        double val = MAT_AT(q, i, i);
        s->data[i] = (val > 0) ? sqrt(val) : 0.0;
    }

    /* Compute U = A * V * S^(-1) or handle transposed case */
    /* Create S^(-1) diagonal matrix */
    CMatrix *s_inv = cmatrix_alloc(size, size);
    for (size_t i = 0; i < size; i++) {
        double sv = s->data[i];
        MAT_AT(s_inv, i, i) = (sv > CLASSIFIER_EPSILON) ? (1.0 / sv) : 0.0;
    }

    CMatrix *u;
    CMatrix *source = transposed ? cmatrix_transpose(a) : cmatrix_clone(a);

    /* U = source * V * S^(-1) */
    CMatrix *temp = cmatrix_multiply(source, v);
    u = cmatrix_multiply(temp, s_inv);

    cmatrix_free(temp);
    cmatrix_free(s_inv);
    cmatrix_free(source);
    cmatrix_free(q);
    cmatrix_free(work_matrix);

    *u_out = u;
    *v_out = v;
    *s_out = s;
}

/* Ruby wrapper: Matrix#SV_decomp */
static VALUE rb_cmatrix_sv_decomp(int argc, VALUE *argv, VALUE self)
{
    CMatrix *m;
    GET_CMATRIX(self, m);

    /* Optional max_sweeps argument (ignored for now, using default) */
    (void)argc;
    (void)argv;

    CMatrix *u, *v;
    CVector *s;
    jacobi_svd(m, &u, &v, &s);

    VALUE rb_u = TypedData_Wrap_Struct(cClassifierMatrix, &cmatrix_type, u);
    VALUE rb_v = TypedData_Wrap_Struct(cClassifierMatrix, &cmatrix_type, v);
    VALUE rb_s = TypedData_Wrap_Struct(cClassifierVector, &cvector_type, s);

    return rb_ary_new_from_args(3, rb_u, rb_v, rb_s);
}

void Init_svd(void)
{
    rb_define_method(cClassifierMatrix, "SV_decomp", rb_cmatrix_sv_decomp, -1);
    rb_define_alias(cClassifierMatrix, "svd", "SV_decomp");
}
