/*
 * classifier_ext.c
 * Main entry point for the Classifier native linear algebra extension
 *
 * This extension provides zero-dependency Vector, Matrix, and SVD
 * implementations for the Classifier gem's LSI functionality.
 */

#include "linalg.h"

VALUE mClassifierLinalg;
VALUE cClassifierVector;
VALUE cClassifierMatrix;

void Init_classifier_ext(void)
{
    /* Define Classifier::Linalg module */
    VALUE mClassifier = rb_define_module("Classifier");
    mClassifierLinalg = rb_define_module_under(mClassifier, "Linalg");

    /* Initialize Vector and Matrix classes */
    Init_vector();
    Init_matrix();
    Init_svd();
}
