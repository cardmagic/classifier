# Classifier reference

Feature reference for the `classifier` gem. Every example here runs against the
version in this repository.

The [README](../README.md) gives the short tour. These pages give the detail.

## Command line

| Page | Contents |
|:--|:--|
| [classifier](cli.md) | Train, classify, and manage models from the shell |
| [keywords](keywords.md) | TF-IDF keyword extraction and term scores |

## Classifiers

| Page | Use it for |
|:--|:--|
| [Bayes](bayes.md) | Fast probabilistic classification. The default choice |
| [Logistic Regression](logistic-regression.md) | Linear classification with calibrated probabilities |
| [LSI](lsi.md) | Semantic similarity, search, related documents, and summaries |
| [k-Nearest Neighbors](knn.md) | Classification with the nearest examples and their votes |

## Vectorization

| Page | Contents |
|:--|:--|
| [TF-IDF](tfidf.md) | Term weights, n-grams, document frequency filters |

## Shared behavior

| Page | Contents |
|:--|:--|
| [Persistence](persistence.md) | Save, load, storage backends, and custom backends |
| [Streaming](streaming.md) | Training on data larger than memory |
| [Configuration](configuration.md) | Global settings and the native extension |

## Which classifier

Start with Bayes. It trains in one pass, needs no fit step, and handles most
text classification tasks.

- Choose **Logistic Regression** when you need a probability per category, and
  you accept a `fit` step after training.
- Choose **LSI** when you need similarity, search, or related documents, and not
  only a label.
- Choose **k-Nearest Neighbors** when you want to see which examples drove the
  answer.
- Choose **TF-IDF** when you want term weights rather than a category.
