/*
 * incremental_svd.c
 * Native C implementation of Brand's incremental SVD operations
 *
 * Provides fast matrix operations for:
 * - Matrix column extension
 * - Vertical stacking (vstack)
 * - Vector subtraction
 * - Batch document projection
 */

#include "linalg.h"

/*
 * Extend a matrix with a new column
 * Returns a new matrix [M | col] with one additional column
 */
CMatrix *cmatrix_extend_column(CMatrix *m, CVector *col)
{
    if (m->rows != col->size) {
        rb_raise(rb_eArgError,
                 "Matrix rows (%ld) must match vector size (%ld)",
                 (long)m->rows, (long)col->size);
    }

    CMatrix *result = cmatrix_alloc(m->rows, m->cols + 1);

    /* Copy existing columns */
    for (size_t i = 0; i < m->rows; i++) {
        memcpy(&MAT_AT(result, i, 0), &MAT_AT(m, i, 0), m->cols * sizeof(double));
        /* Add new column */
        MAT_AT(result, i, m->cols) = col->data[i];
    }

    return result;
}

/*
 * Vertically stack two matrices
 * Returns a new matrix [top; bottom]
 */
CMatrix *cmatrix_vstack(CMatrix *top, CMatrix *bottom)
{
    if (top->cols != bottom->cols) {
        rb_raise(rb_eArgError,
                 "Matrices must have same column count: %ld vs %ld",
                 (long)top->cols, (long)bottom->cols);
    }

    size_t new_rows = top->rows + bottom->rows;
    CMatrix *result = cmatrix_alloc(new_rows, top->cols);

    /* Copy top matrix */
    memcpy(result->data, top->data, top->rows * top->cols * sizeof(double));

    /* Copy bottom matrix */
    memcpy(result->data + top->rows * top->cols,
           bottom->data,
           bottom->rows * bottom->cols * sizeof(double));

    return result;
}

/*
 * Vector subtraction: a - b
 */
CVector *cvector_subtract(CVector *a, CVector *b)
{
    if (a->size != b->size) {
        rb_raise(rb_eArgError,
                 "Vector sizes must match: %ld vs %ld",
                 (long)a->size, (long)b->size);
    }

    CVector *result = cvector_alloc(a->size);
    for (size_t i = 0; i < a->size; i++) {
        result->data[i] = a->data[i] - b->data[i];
    }
    return result;
}

/*
 * Batch project multiple vectors onto U matrix
 * Computes lsi_vector = U^T * raw_vector for each vector
 * This is the most performance-critical operation for incremental updates
 */
void cbatch_project(CMatrix *u, CVector **raw_vectors, size_t num_vectors,
                    CVector **lsi_vectors_out)
{
    size_t m = u->rows;    /* vocabulary size */
    size_t k = u->cols;    /* rank */

    for (size_t v = 0; v < num_vectors; v++) {
        CVector *raw = raw_vectors[v];
        if (raw->size != m) {
            rb_raise(rb_eArgError,
                     "Vector %ld size (%ld) must match matrix rows (%ld)",
                     (long)v, (long)raw->size, (long)m);
        }

        CVector *lsi = cvector_alloc(k);

        /* Compute U^T * raw (project onto k-dimensional space) */
        for (size_t j = 0; j < k; j++) {
            double sum = 0.0;
            for (size_t i = 0; i < m; i++) {
                sum += MAT_AT(u, i, j) * raw->data[i];
            }
            lsi->data[j] = sum;
        }

        lsi_vectors_out[v] = lsi;
    }
}

/*
 * Build the K matrix for Brand's algorithm when rank grows
 * K = | diag(s)  m_vec |
 *     |   0     p_norm |
 */
static CMatrix *build_k_matrix_with_growth(CVector *s, CVector *m_vec, double p_norm)
{
    size_t k = s->size;
    CMatrix *result = cmatrix_alloc(k + 1, k + 1);

    /* First k rows: diagonal s values and m_vec in last column */
    for (size_t i = 0; i < k; i++) {
        MAT_AT(result, i, i) = s->data[i];
        MAT_AT(result, i, k) = m_vec->data[i];
    }

    /* Last row: zeros except p_norm in last position */
    MAT_AT(result, k, k) = p_norm;

    return result;
}

/*
 * Perform one incremental SVD update using Brand's algorithm
 *
 * @param u Current U matrix (m x k)
 * @param s Current singular values (k values)
 * @param c New document vector (m x 1)
 * @param max_rank Maximum rank to maintain
 * @param epsilon Threshold for detecting new directions
 * @param u_out Output: updated U matrix
 * @param s_out Output: updated singular values
 */
static void incremental_update(CMatrix *u, CVector *s, CVector *c, int max_rank,
                                double epsilon, CMatrix **u_out, CVector **s_out)
{
    size_t m = u->rows;
    size_t k = u->cols;

    /* Step 1: Project c onto column space of U */
    /* m_vec = U^T * c */
    CVector *m_vec = cvector_alloc(k);
    for (size_t j = 0; j < k; j++) {
        double sum = 0.0;
        for (size_t i = 0; i < m; i++) {
            sum += MAT_AT(u, i, j) * c->data[i];
        }
        m_vec->data[j] = sum;
    }

    /* Step 2: Compute residual p = c - U * m_vec */
    CVector *u_times_m = cmatrix_multiply_vector(u, m_vec);
    CVector *p = cvector_subtract(c, u_times_m);
    double p_norm = cvector_magnitude(p);

    cvector_free(u_times_m);

    if (p_norm > epsilon) {
        /* New direction found - rank may increase */

        /* Step 3: Normalize residual */
        CVector *p_hat = cvector_alloc(m);
        double inv_p_norm = 1.0 / p_norm;
        for (size_t i = 0; i < m; i++) {
            p_hat->data[i] = p->data[i] * inv_p_norm;
        }

        /* Step 4: Build K matrix */
        CMatrix *k_mat = build_k_matrix_with_growth(s, m_vec, p_norm);

        /* Step 5: SVD of K matrix */
        CMatrix *u_prime, *v_prime;
        CVector *s_prime;
        jacobi_svd(k_mat, &u_prime, &v_prime, &s_prime);
        cmatrix_free(k_mat);
        cmatrix_free(v_prime);

        /* Step 6: Update U = [U | p_hat] * U' */
        CMatrix *u_extended = cmatrix_extend_column(u, p_hat);
        CMatrix *u_new = cmatrix_multiply(u_extended, u_prime);
        cmatrix_free(u_extended);
        cmatrix_free(u_prime);
        cvector_free(p_hat);

        /* Truncate if needed */
        if (s_prime->size > (size_t)max_rank) {
            /* Create truncated U (keep first max_rank columns) */
            CMatrix *u_trunc = cmatrix_alloc(u_new->rows, (size_t)max_rank);
            for (size_t i = 0; i < u_new->rows; i++) {
                memcpy(&MAT_AT(u_trunc, i, 0), &MAT_AT(u_new, i, 0),
                       (size_t)max_rank * sizeof(double));
            }
            cmatrix_free(u_new);
            u_new = u_trunc;

            /* Truncate singular values */
            CVector *s_trunc = cvector_alloc((size_t)max_rank);
            memcpy(s_trunc->data, s_prime->data, (size_t)max_rank * sizeof(double));
            cvector_free(s_prime);
            s_prime = s_trunc;
        }

        *u_out = u_new;
        *s_out = s_prime;
    } else {
        /* Vector in span - use simpler update */
        /* For now, just return unchanged (projection handles this) */
        *u_out = cmatrix_alloc(u->rows, u->cols);
        memcpy((*u_out)->data, u->data, u->rows * u->cols * sizeof(double));
        *s_out = cvector_alloc(s->size);
        memcpy((*s_out)->data, s->data, s->size * sizeof(double));
    }

    cvector_free(p);
    cvector_free(m_vec);
}

/* ========== Ruby Wrappers ========== */

/*
 * Matrix.extend_column(matrix, vector)
 * Returns [matrix | vector]
 */
static VALUE rb_cmatrix_extend_column(VALUE klass, VALUE rb_matrix, VALUE rb_vector)
{
    CMatrix *m;
    CVector *v;

    GET_CMATRIX(rb_matrix, m);
    GET_CVECTOR(rb_vector, v);

    CMatrix *result = cmatrix_extend_column(m, v);
    return TypedData_Wrap_Struct(klass, &cmatrix_type, result);

    (void)klass;
}

/*
 * Matrix.vstack(top, bottom)
 * Vertically stack two matrices
 */
static VALUE rb_cmatrix_vstack(VALUE klass, VALUE rb_top, VALUE rb_bottom)
{
    CMatrix *top, *bottom;

    GET_CMATRIX(rb_top, top);
    GET_CMATRIX(rb_bottom, bottom);

    CMatrix *result = cmatrix_vstack(top, bottom);
    return TypedData_Wrap_Struct(klass, &cmatrix_type, result);

    (void)klass;
}

/*
 * Matrix.zeros(rows, cols)
 * Create a zero matrix
 */
static VALUE rb_cmatrix_zeros(VALUE klass, VALUE rb_rows, VALUE rb_cols)
{
    size_t rows = NUM2SIZET(rb_rows);
    size_t cols = NUM2SIZET(rb_cols);

    CMatrix *result = cmatrix_alloc(rows, cols);
    /* Already zero-initialized by cmatrix_alloc */

    return TypedData_Wrap_Struct(klass, &cmatrix_type, result);

    (void)klass;
}

/*
 * Vector#-(other)
 * Vector subtraction
 */
static VALUE rb_cvector_subtract(VALUE self, VALUE other)
{
    CVector *a, *b;

    GET_CVECTOR(self, a);

    if (rb_obj_is_kind_of(other, cClassifierVector)) {
        GET_CVECTOR(other, b);
        CVector *result = cvector_subtract(a, b);
        return TypedData_Wrap_Struct(cClassifierVector, &cvector_type, result);
    }

    rb_raise(rb_eTypeError, "Cannot subtract %s from Vector",
             rb_obj_classname(other));
    return Qnil;
}

/*
 * Matrix#batch_project(vectors_array)
 * Project multiple vectors onto this matrix (as U)
 * Returns array of projected vectors
 *
 * This is the high-performance batch operation for re-projecting documents
 */
static VALUE rb_cmatrix_batch_project(VALUE self, VALUE rb_vectors)
{
    CMatrix *u;
    GET_CMATRIX(self, u);

    Check_Type(rb_vectors, T_ARRAY);
    long num_vectors = RARRAY_LEN(rb_vectors);

    if (num_vectors == 0) {
        return rb_ary_new();
    }

    /* Convert Ruby vectors to C vectors */
    CVector **raw_vectors = ALLOC_N(CVector *, num_vectors);
    for (long i = 0; i < num_vectors; i++) {
        VALUE rb_vec = rb_ary_entry(rb_vectors, i);
        if (!rb_obj_is_kind_of(rb_vec, cClassifierVector)) {
            xfree(raw_vectors);
            rb_raise(rb_eTypeError, "Expected array of Vectors");
        }
        GET_CVECTOR(rb_vec, raw_vectors[i]);
    }

    /* Allocate output array */
    CVector **lsi_vectors = ALLOC_N(CVector *, num_vectors);

    /* Perform batch projection */
    cbatch_project(u, raw_vectors, (size_t)num_vectors, lsi_vectors);

    /* Convert results to Ruby */
    VALUE result = rb_ary_new_capa(num_vectors);
    for (long i = 0; i < num_vectors; i++) {
        VALUE rb_lsi = TypedData_Wrap_Struct(cClassifierVector, &cvector_type,
                                              lsi_vectors[i]);
        rb_ary_push(result, rb_lsi);
    }

    xfree(raw_vectors);
    xfree(lsi_vectors);

    return result;
}

/*
 * Matrix#incremental_svd_update(singular_values, new_vector, max_rank, epsilon)
 * Perform one Brand's incremental SVD update
 * Returns [new_u, new_singular_values]
 */
static VALUE rb_cmatrix_incremental_update(VALUE self, VALUE rb_s, VALUE rb_c,
                                            VALUE rb_max_rank, VALUE rb_epsilon)
{
    CMatrix *u;
    CVector *s, *c;

    GET_CMATRIX(self, u);
    GET_CVECTOR(rb_s, s);
    GET_CVECTOR(rb_c, c);

    int max_rank = NUM2INT(rb_max_rank);
    double epsilon = NUM2DBL(rb_epsilon);

    CMatrix *u_new;
    CVector *s_new;

    incremental_update(u, s, c, max_rank, epsilon, &u_new, &s_new);

    VALUE rb_u_new = TypedData_Wrap_Struct(cClassifierMatrix, &cmatrix_type, u_new);
    VALUE rb_s_new = TypedData_Wrap_Struct(cClassifierVector, &cvector_type, s_new);

    return rb_ary_new_from_args(2, rb_u_new, rb_s_new);
}

void Init_incremental_svd(void)
{
    /* Matrix class methods for incremental SVD */
    rb_define_singleton_method(cClassifierMatrix, "extend_column",
                               rb_cmatrix_extend_column, 2);
    rb_define_singleton_method(cClassifierMatrix, "vstack",
                               rb_cmatrix_vstack, 2);
    rb_define_singleton_method(cClassifierMatrix, "zeros",
                               rb_cmatrix_zeros, 2);

    /* Instance methods */
    rb_define_method(cClassifierMatrix, "batch_project",
                     rb_cmatrix_batch_project, 1);
    rb_define_method(cClassifierMatrix, "incremental_svd_update",
                     rb_cmatrix_incremental_update, 4);

    /* Vector subtraction */
    rb_define_method(cClassifierVector, "-", rb_cvector_subtract, 1);
}
