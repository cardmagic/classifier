#ifndef CLASSIFIER_LINALG_H
#define CLASSIFIER_LINALG_H

#include <ruby.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* Epsilon for numerical comparisons */
#define CLASSIFIER_EPSILON 1e-10

/* Vector structure */
typedef struct {
    size_t size;
    double *data;
    int is_col;  /* 0 = row vector, 1 = column vector */
} CVector;

/* Matrix structure */
typedef struct {
    size_t rows;
    size_t cols;
    double *data;  /* Row-major storage */
} CMatrix;

/* Ruby class references */
extern VALUE cClassifierVector;
extern VALUE cClassifierMatrix;
extern VALUE mClassifierLinalg;

/* Vector functions */
void Init_vector(void);
CVector *cvector_alloc(size_t size);
void cvector_free(void *ptr);
double cvector_magnitude(CVector *v);
CVector *cvector_normalize(CVector *v);
double cvector_sum(CVector *v);
double cvector_dot(CVector *a, CVector *b);

/* Matrix functions */
void Init_matrix(void);
CMatrix *cmatrix_alloc(size_t rows, size_t cols);
void cmatrix_free(void *ptr);
CMatrix *cmatrix_transpose(CMatrix *m);
CMatrix *cmatrix_multiply(CMatrix *a, CMatrix *b);
CVector *cmatrix_multiply_vector(CMatrix *m, CVector *v);
CMatrix *cmatrix_diagonal(CVector *v);

/* SVD functions */
void Init_svd(void);
void jacobi_svd(CMatrix *a, CMatrix **u, CMatrix **v, CVector **s);

/* TypedData definitions */
extern const rb_data_type_t cvector_type;
extern const rb_data_type_t cmatrix_type;

/* Helper macros */
#define GET_CVECTOR(obj, ptr) TypedData_Get_Struct(obj, CVector, &cvector_type, ptr)
#define GET_CMATRIX(obj, ptr) TypedData_Get_Struct(obj, CMatrix, &cmatrix_type, ptr)

/* Matrix element access (row-major) */
#define MAT_AT(m, i, j) ((m)->data[(i) * (m)->cols + (j)])

#endif /* CLASSIFIER_LINALG_H */
