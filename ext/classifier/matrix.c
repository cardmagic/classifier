/*
 * matrix.c
 * Matrix implementation for Classifier native linear algebra
 */

#include "linalg.h"

const rb_data_type_t cmatrix_type = {
    .wrap_struct_name = "Classifier::Linalg::Matrix",
    .function = {
        .dmark = NULL,
        .dfree = cmatrix_free,
        .dsize = NULL,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

/* Allocate a new CMatrix */
CMatrix *cmatrix_alloc(size_t rows, size_t cols)
{
    CMatrix *m = ALLOC(CMatrix);
    m->rows = rows;
    m->cols = cols;
    m->data = ALLOC_N(double, rows * cols);
    memset(m->data, 0, rows * cols * sizeof(double));
    return m;
}

/* Free a CMatrix */
void cmatrix_free(void *ptr)
{
    CMatrix *m = (CMatrix *)ptr;
    if (m) {
        if (m->data) xfree(m->data);
        xfree(m);
    }
}

/* Transpose a matrix */
CMatrix *cmatrix_transpose(CMatrix *m)
{
    CMatrix *result = cmatrix_alloc(m->cols, m->rows);
    for (size_t i = 0; i < m->rows; i++) {
        for (size_t j = 0; j < m->cols; j++) {
            MAT_AT(result, j, i) = MAT_AT(m, i, j);
        }
    }
    return result;
}

/* Matrix multiplication */
CMatrix *cmatrix_multiply(CMatrix *a, CMatrix *b)
{
    if (a->cols != b->rows) {
        rb_raise(rb_eArgError, "Matrix dimensions don't match for multiplication: %ldx%ld * %ldx%ld",
                 (long)a->rows, (long)a->cols, (long)b->rows, (long)b->cols);
    }

    CMatrix *result = cmatrix_alloc(a->rows, b->cols);

    for (size_t i = 0; i < a->rows; i++) {
        for (size_t j = 0; j < b->cols; j++) {
            double sum = 0.0;
            for (size_t k = 0; k < a->cols; k++) {
                sum += MAT_AT(a, i, k) * MAT_AT(b, k, j);
            }
            MAT_AT(result, i, j) = sum;
        }
    }
    return result;
}

/* Matrix-vector multiplication */
CVector *cmatrix_multiply_vector(CMatrix *m, CVector *v)
{
    if (m->cols != v->size) {
        rb_raise(rb_eArgError, "Matrix columns (%ld) must match vector size (%ld)",
                 (long)m->cols, (long)v->size);
    }

    CVector *result = cvector_alloc(m->rows);

    for (size_t i = 0; i < m->rows; i++) {
        double sum = 0.0;
        for (size_t j = 0; j < m->cols; j++) {
            sum += MAT_AT(m, i, j) * v->data[j];
        }
        result->data[i] = sum;
    }
    return result;
}

/* Create diagonal matrix from vector */
CMatrix *cmatrix_diagonal(CVector *v)
{
    CMatrix *result = cmatrix_alloc(v->size, v->size);
    for (size_t i = 0; i < v->size; i++) {
        MAT_AT(result, i, i) = v->data[i];
    }
    return result;
}

/* Ruby allocation function */
static VALUE rb_cmatrix_alloc_func(VALUE klass)
{
    CMatrix *m = cmatrix_alloc(0, 0);
    return TypedData_Wrap_Struct(klass, &cmatrix_type, m);
}

/*
 * Matrix.alloc(*rows)
 * Create a new matrix from nested arrays
 */
static VALUE rb_cmatrix_s_alloc(int argc, VALUE *argv, VALUE klass)
{
    CMatrix *m;
    VALUE result;

    if (argc == 0) {
        rb_raise(rb_eArgError, "Matrix.alloc requires at least one row");
    }

    /* Handle single array argument containing rows */
    VALUE rows_ary;
    if (argc == 1 && RB_TYPE_P(argv[0], T_ARRAY)) {
        VALUE first = rb_ary_entry(argv[0], 0);
        if (RB_TYPE_P(first, T_ARRAY)) {
            rows_ary = argv[0];
        } else {
            /* Single row */
            rows_ary = rb_ary_new_from_values(argc, argv);
        }
    } else {
        rows_ary = rb_ary_new_from_values(argc, argv);
    }

    long num_rows = RARRAY_LEN(rows_ary);
    if (num_rows == 0) {
        rb_raise(rb_eArgError, "Matrix cannot be empty");
    }

    VALUE first_row = rb_ary_entry(rows_ary, 0);
    long num_cols = RARRAY_LEN(first_row);

    m = cmatrix_alloc((size_t)num_rows, (size_t)num_cols);

    for (long i = 0; i < num_rows; i++) {
        VALUE row = rb_ary_entry(rows_ary, i);
        if (RARRAY_LEN(row) != num_cols) {
            cmatrix_free(m);
            rb_raise(rb_eArgError, "All rows must have the same length");
        }
        for (long j = 0; j < num_cols; j++) {
            MAT_AT(m, i, j) = NUM2DBL(rb_ary_entry(row, j));
        }
    }

    result = TypedData_Wrap_Struct(klass, &cmatrix_type, m);
    return result;
}

/*
 * Matrix.diag(vector_or_array)
 * Create diagonal matrix from vector
 */
static VALUE rb_cmatrix_s_diag(VALUE klass, VALUE arg)
{
    CVector *v;
    CMatrix *m;
    int free_v = 0;

    if (rb_obj_is_kind_of(arg, cClassifierVector)) {
        GET_CVECTOR(arg, v);
    } else if (RB_TYPE_P(arg, T_ARRAY)) {
        long len = RARRAY_LEN(arg);
        v = cvector_alloc((size_t)len);
        free_v = 1;
        for (long i = 0; i < len; i++) {
            v->data[i] = NUM2DBL(rb_ary_entry(arg, i));
        }
    } else {
        rb_raise(rb_eTypeError, "Expected Vector or Array");
        return Qnil;
    }

    m = cmatrix_diagonal(v);
    if (free_v) cvector_free(v);

    return TypedData_Wrap_Struct(klass, &cmatrix_type, m);
}

/* Matrix#size -> [rows, cols] */
static VALUE rb_cmatrix_size(VALUE self)
{
    CMatrix *m;
    GET_CMATRIX(self, m);
    return rb_ary_new_from_args(2, SIZET2NUM(m->rows), SIZET2NUM(m->cols));
}

/* Matrix#row_size */
static VALUE rb_cmatrix_row_size(VALUE self)
{
    CMatrix *m;
    GET_CMATRIX(self, m);
    return SIZET2NUM(m->rows);
}

/* Matrix#column_size */
static VALUE rb_cmatrix_column_size(VALUE self)
{
    CMatrix *m;
    GET_CMATRIX(self, m);
    return SIZET2NUM(m->cols);
}

/* Matrix#[](i, j) */
static VALUE rb_cmatrix_aref(VALUE self, VALUE row, VALUE col)
{
    CMatrix *m;
    GET_CMATRIX(self, m);
    long i = NUM2LONG(row);
    long j = NUM2LONG(col);

    if (i < 0) i += m->rows;
    if (j < 0) j += m->cols;
    if (i < 0 || (size_t)i >= m->rows || j < 0 || (size_t)j >= m->cols) {
        rb_raise(rb_eIndexError, "index out of bounds");
    }

    return DBL2NUM(MAT_AT(m, i, j));
}

/* Matrix#[]=(i, j, val) */
static VALUE rb_cmatrix_aset(VALUE self, VALUE row, VALUE col, VALUE val)
{
    CMatrix *m;
    GET_CMATRIX(self, m);
    long i = NUM2LONG(row);
    long j = NUM2LONG(col);

    if (i < 0) i += m->rows;
    if (j < 0) j += m->cols;
    if (i < 0 || (size_t)i >= m->rows || j < 0 || (size_t)j >= m->cols) {
        rb_raise(rb_eIndexError, "index out of bounds");
    }

    MAT_AT(m, i, j) = NUM2DBL(val);
    return val;
}

/* Matrix#trans (transpose) */
static VALUE rb_cmatrix_trans(VALUE self)
{
    CMatrix *m;
    GET_CMATRIX(self, m);
    CMatrix *result = cmatrix_transpose(m);
    return TypedData_Wrap_Struct(cClassifierMatrix, &cmatrix_type, result);
}

/* Matrix#column(n) -> Vector */
static VALUE rb_cmatrix_column(VALUE self, VALUE col_idx)
{
    CMatrix *m;
    GET_CMATRIX(self, m);
    long j = NUM2LONG(col_idx);

    if (j < 0) j += m->cols;
    if (j < 0 || (size_t)j >= m->cols) {
        rb_raise(rb_eIndexError, "column index out of bounds");
    }

    CVector *v = cvector_alloc(m->rows);
    v->is_col = 1;
    for (size_t i = 0; i < m->rows; i++) {
        v->data[i] = MAT_AT(m, i, j);
    }

    return TypedData_Wrap_Struct(cClassifierVector, &cvector_type, v);
}

/* Matrix#row(n) -> Vector */
static VALUE rb_cmatrix_row(VALUE self, VALUE row_idx)
{
    CMatrix *m;
    GET_CMATRIX(self, m);
    long i = NUM2LONG(row_idx);

    if (i < 0) i += m->rows;
    if (i < 0 || (size_t)i >= m->rows) {
        rb_raise(rb_eIndexError, "row index out of bounds");
    }

    CVector *v = cvector_alloc(m->cols);
    v->is_col = 0;
    memcpy(v->data, &MAT_AT(m, i, 0), m->cols * sizeof(double));

    return TypedData_Wrap_Struct(cClassifierVector, &cvector_type, v);
}

/* Matrix#to_a */
static VALUE rb_cmatrix_to_a(VALUE self)
{
    CMatrix *m;
    GET_CMATRIX(self, m);
    VALUE ary = rb_ary_new_capa((long)m->rows);

    for (size_t i = 0; i < m->rows; i++) {
        VALUE row = rb_ary_new_capa((long)m->cols);
        for (size_t j = 0; j < m->cols; j++) {
            rb_ary_push(row, DBL2NUM(MAT_AT(m, i, j)));
        }
        rb_ary_push(ary, row);
    }
    return ary;
}

/* Matrix#* - multiply with matrix or vector */
static VALUE rb_cmatrix_mul(VALUE self, VALUE other)
{
    CMatrix *m;
    GET_CMATRIX(self, m);

    if (rb_obj_is_kind_of(other, cClassifierMatrix)) {
        CMatrix *b;
        GET_CMATRIX(other, b);
        CMatrix *result = cmatrix_multiply(m, b);
        return TypedData_Wrap_Struct(cClassifierMatrix, &cmatrix_type, result);
    } else if (rb_obj_is_kind_of(other, cClassifierVector)) {
        CVector *v;
        GET_CVECTOR(other, v);
        CVector *result = cmatrix_multiply_vector(m, v);
        return TypedData_Wrap_Struct(cClassifierVector, &cvector_type, result);
    } else if (RB_TYPE_P(other, T_FLOAT) || RB_TYPE_P(other, T_FIXNUM)) {
        /* Scalar multiplication */
        double scalar = NUM2DBL(other);
        CMatrix *result = cmatrix_alloc(m->rows, m->cols);
        for (size_t i = 0; i < m->rows * m->cols; i++) {
            result->data[i] = m->data[i] * scalar;
        }
        return TypedData_Wrap_Struct(cClassifierMatrix, &cmatrix_type, result);
    }

    rb_raise(rb_eTypeError, "Cannot multiply Matrix with %s", rb_obj_classname(other));
    return Qnil;
}

/* Matrix#_dump for Marshal */
static VALUE rb_cmatrix_dump(VALUE self, VALUE depth)
{
    CMatrix *m;
    GET_CMATRIX(self, m);
    VALUE ary = rb_cmatrix_to_a(self);
    return rb_marshal_dump(ary, Qnil);
}

/* Matrix._load for Marshal */
static VALUE rb_cmatrix_s_load(VALUE klass, VALUE str)
{
    VALUE ary = rb_marshal_load(str);
    long argc = RARRAY_LEN(ary);
    VALUE *argv = RARRAY_PTR(ary);
    return rb_cmatrix_s_alloc((int)argc, argv, klass);
}

void Init_matrix(void)
{
    cClassifierMatrix = rb_define_class_under(mClassifierLinalg, "Matrix", rb_cObject);

    rb_define_alloc_func(cClassifierMatrix, rb_cmatrix_alloc_func);
    rb_define_singleton_method(cClassifierMatrix, "alloc", rb_cmatrix_s_alloc, -1);
    rb_define_singleton_method(cClassifierMatrix, "diag", rb_cmatrix_s_diag, 1);
    rb_define_singleton_method(cClassifierMatrix, "diagonal", rb_cmatrix_s_diag, 1);
    rb_define_singleton_method(cClassifierMatrix, "_load", rb_cmatrix_s_load, 1);

    rb_define_method(cClassifierMatrix, "size", rb_cmatrix_size, 0);
    rb_define_method(cClassifierMatrix, "row_size", rb_cmatrix_row_size, 0);
    rb_define_method(cClassifierMatrix, "column_size", rb_cmatrix_column_size, 0);
    rb_define_method(cClassifierMatrix, "[]", rb_cmatrix_aref, 2);
    rb_define_method(cClassifierMatrix, "[]=", rb_cmatrix_aset, 3);
    rb_define_method(cClassifierMatrix, "trans", rb_cmatrix_trans, 0);
    rb_define_alias(cClassifierMatrix, "transpose", "trans");
    rb_define_method(cClassifierMatrix, "column", rb_cmatrix_column, 1);
    rb_define_method(cClassifierMatrix, "row", rb_cmatrix_row, 1);
    rb_define_method(cClassifierMatrix, "to_a", rb_cmatrix_to_a, 0);
    rb_define_method(cClassifierMatrix, "*", rb_cmatrix_mul, 1);
    rb_define_method(cClassifierMatrix, "_dump", rb_cmatrix_dump, 1);
}
