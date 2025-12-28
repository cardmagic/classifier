/*
 * vector.c
 * Vector implementation for Classifier native linear algebra
 */

#include "linalg.h"

const rb_data_type_t cvector_type = {
    .wrap_struct_name = "Classifier::Linalg::Vector",
    .function = {
        .dmark = NULL,
        .dfree = cvector_free,
        .dsize = NULL,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

/* Allocate a new CVector */
CVector *cvector_alloc(size_t size)
{
    CVector *v = ALLOC(CVector);
    v->size = size;
    v->data = ALLOC_N(double, size);
    v->is_col = 0;  /* Default to row vector */
    memset(v->data, 0, size * sizeof(double));
    return v;
}

/* Free a CVector */
void cvector_free(void *ptr)
{
    CVector *v = (CVector *)ptr;
    if (v) {
        if (v->data) xfree(v->data);
        xfree(v);
    }
}

/* Calculate magnitude (Euclidean norm) */
double cvector_magnitude(CVector *v)
{
    double sum = 0.0;
    for (size_t i = 0; i < v->size; i++) {
        sum += v->data[i] * v->data[i];
    }
    return sqrt(sum);
}

/* Return normalized copy */
CVector *cvector_normalize(CVector *v)
{
    CVector *result = cvector_alloc(v->size);
    result->is_col = v->is_col;
    double mag = cvector_magnitude(v);

    if (mag <= CLASSIFIER_EPSILON) {
        /* Return zero vector if magnitude is too small */
        return result;
    }

    for (size_t i = 0; i < v->size; i++) {
        result->data[i] = v->data[i] / mag;
    }
    return result;
}

/* Sum all elements */
double cvector_sum(CVector *v)
{
    double sum = 0.0;
    for (size_t i = 0; i < v->size; i++) {
        sum += v->data[i];
    }
    return sum;
}

/* Dot product */
double cvector_dot(CVector *a, CVector *b)
{
    if (a->size != b->size) {
        rb_raise(rb_eArgError, "Vector sizes must match for dot product");
    }
    double sum = 0.0;
    for (size_t i = 0; i < a->size; i++) {
        sum += a->data[i] * b->data[i];
    }
    return sum;
}

/* Ruby allocation function */
static VALUE rb_cvector_alloc(VALUE klass)
{
    CVector *v = cvector_alloc(0);
    return TypedData_Wrap_Struct(klass, &cvector_type, v);
}

/*
 * Vector.alloc(size_or_array)
 * Create a new vector from size (zero-filled) or array of values
 */
static VALUE rb_cvector_s_alloc(VALUE klass, VALUE arg)
{
    CVector *v;
    VALUE result;

    if (RB_TYPE_P(arg, T_ARRAY)) {
        long len = RARRAY_LEN(arg);
        v = cvector_alloc((size_t)len);
        for (long i = 0; i < len; i++) {
            v->data[i] = NUM2DBL(rb_ary_entry(arg, i));
        }
    } else {
        size_t size = NUM2SIZET(arg);
        v = cvector_alloc(size);
    }

    result = TypedData_Wrap_Struct(klass, &cvector_type, v);
    return result;
}

/* Vector#size */
static VALUE rb_cvector_size(VALUE self)
{
    CVector *v;
    GET_CVECTOR(self, v);
    return SIZET2NUM(v->size);
}

/* Vector#[] */
static VALUE rb_cvector_aref(VALUE self, VALUE idx)
{
    CVector *v;
    GET_CVECTOR(self, v);
    long i = NUM2LONG(idx);

    if (i < 0) i += v->size;
    if (i < 0 || (size_t)i >= v->size) {
        rb_raise(rb_eIndexError, "index %ld out of bounds", i);
    }

    return DBL2NUM(v->data[i]);
}

/* Vector#[]= */
static VALUE rb_cvector_aset(VALUE self, VALUE idx, VALUE val)
{
    CVector *v;
    GET_CVECTOR(self, v);
    long i = NUM2LONG(idx);

    if (i < 0) i += v->size;
    if (i < 0 || (size_t)i >= v->size) {
        rb_raise(rb_eIndexError, "index %ld out of bounds", i);
    }

    v->data[i] = NUM2DBL(val);
    return val;
}

/* Vector#to_a */
static VALUE rb_cvector_to_a(VALUE self)
{
    CVector *v;
    GET_CVECTOR(self, v);
    VALUE ary = rb_ary_new_capa((long)v->size);

    for (size_t i = 0; i < v->size; i++) {
        rb_ary_push(ary, DBL2NUM(v->data[i]));
    }
    return ary;
}

/* Vector#sum */
static VALUE rb_cvector_sum(VALUE self)
{
    CVector *v;
    GET_CVECTOR(self, v);
    return DBL2NUM(cvector_sum(v));
}

/* Vector#each */
static VALUE rb_cvector_each(VALUE self)
{
    CVector *v;
    GET_CVECTOR(self, v);

    RETURN_ENUMERATOR(self, 0, 0);

    for (size_t i = 0; i < v->size; i++) {
        rb_yield(DBL2NUM(v->data[i]));
    }
    return self;
}

/* Vector#collect (map) */
static VALUE rb_cvector_collect(VALUE self)
{
    CVector *v;
    GET_CVECTOR(self, v);

    RETURN_ENUMERATOR(self, 0, 0);

    CVector *result = cvector_alloc(v->size);
    result->is_col = v->is_col;

    for (size_t i = 0; i < v->size; i++) {
        VALUE val = rb_yield(DBL2NUM(v->data[i]));
        result->data[i] = NUM2DBL(val);
    }

    return TypedData_Wrap_Struct(cClassifierVector, &cvector_type, result);
}

/* Vector#normalize */
static VALUE rb_cvector_normalize(VALUE self)
{
    CVector *v;
    GET_CVECTOR(self, v);
    CVector *result = cvector_normalize(v);
    return TypedData_Wrap_Struct(cClassifierVector, &cvector_type, result);
}

/* Vector#row - return self as row vector */
static VALUE rb_cvector_row(VALUE self)
{
    CVector *v;
    GET_CVECTOR(self, v);

    CVector *result = cvector_alloc(v->size);
    memcpy(result->data, v->data, v->size * sizeof(double));
    result->is_col = 0;

    return TypedData_Wrap_Struct(cClassifierVector, &cvector_type, result);
}

/* Vector#col - return self as column vector */
static VALUE rb_cvector_col(VALUE self)
{
    CVector *v;
    GET_CVECTOR(self, v);

    CVector *result = cvector_alloc(v->size);
    memcpy(result->data, v->data, v->size * sizeof(double));
    result->is_col = 1;

    return TypedData_Wrap_Struct(cClassifierVector, &cvector_type, result);
}

/* Vector#* - dot product with vector, or matrix multiplication */
static VALUE rb_cvector_mul(VALUE self, VALUE other)
{
    CVector *v;
    GET_CVECTOR(self, v);

    if (rb_obj_is_kind_of(other, cClassifierVector)) {
        CVector *w;
        GET_CVECTOR(other, w);
        return DBL2NUM(cvector_dot(v, w));
    } else if (RB_TYPE_P(other, T_FLOAT) || RB_TYPE_P(other, T_FIXNUM)) {
        /* Scalar multiplication */
        double scalar = NUM2DBL(other);
        CVector *result = cvector_alloc(v->size);
        result->is_col = v->is_col;
        for (size_t i = 0; i < v->size; i++) {
            result->data[i] = v->data[i] * scalar;
        }
        return TypedData_Wrap_Struct(cClassifierVector, &cvector_type, result);
    }

    rb_raise(rb_eTypeError, "Cannot multiply Vector with %s", rb_obj_classname(other));
    return Qnil;
}

/* Vector#_dump for Marshal */
static VALUE rb_cvector_dump(VALUE self, VALUE depth)
{
    CVector *v;
    GET_CVECTOR(self, v);
    VALUE ary = rb_cvector_to_a(self);
    rb_ary_push(ary, v->is_col ? Qtrue : Qfalse);
    return rb_marshal_dump(ary, Qnil);
}

/* Vector._load for Marshal */
static VALUE rb_cvector_s_load(VALUE klass, VALUE str)
{
    VALUE ary = rb_marshal_load(str);
    VALUE is_col = rb_ary_pop(ary);
    VALUE result = rb_cvector_s_alloc(klass, ary);
    CVector *v;
    GET_CVECTOR(result, v);
    v->is_col = RTEST(is_col) ? 1 : 0;
    return result;
}

void Init_vector(void)
{
    cClassifierVector = rb_define_class_under(mClassifierLinalg, "Vector", rb_cObject);

    rb_define_alloc_func(cClassifierVector, rb_cvector_alloc);
    rb_define_singleton_method(cClassifierVector, "alloc", rb_cvector_s_alloc, 1);
    rb_define_singleton_method(cClassifierVector, "_load", rb_cvector_s_load, 1);

    rb_define_method(cClassifierVector, "size", rb_cvector_size, 0);
    rb_define_method(cClassifierVector, "[]", rb_cvector_aref, 1);
    rb_define_method(cClassifierVector, "[]=", rb_cvector_aset, 2);
    rb_define_method(cClassifierVector, "to_a", rb_cvector_to_a, 0);
    rb_define_method(cClassifierVector, "sum", rb_cvector_sum, 0);
    rb_define_method(cClassifierVector, "each", rb_cvector_each, 0);
    rb_define_method(cClassifierVector, "collect", rb_cvector_collect, 0);
    rb_define_alias(cClassifierVector, "map", "collect");
    rb_define_method(cClassifierVector, "normalize", rb_cvector_normalize, 0);
    rb_define_method(cClassifierVector, "row", rb_cvector_row, 0);
    rb_define_method(cClassifierVector, "col", rb_cvector_col, 0);
    rb_define_method(cClassifierVector, "*", rb_cvector_mul, 1);
    rb_define_method(cClassifierVector, "_dump", rb_cvector_dump, 1);

    rb_include_module(cClassifierVector, rb_mEnumerable);
}
