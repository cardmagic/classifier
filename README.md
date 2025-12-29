# Classifier

[![Gem Version](https://badge.fury.io/rb/classifier.svg)](https://badge.fury.io/rb/classifier)
[![CI](https://github.com/cardmagic/classifier/actions/workflows/ruby.yml/badge.svg)](https://github.com/cardmagic/classifier/actions/workflows/ruby.yml)
[![License: LGPL](https://img.shields.io/badge/License-LGPL_2.1-blue.svg)](https://opensource.org/licenses/LGPL-2.1)

Text classification in Ruby. Five algorithms, native performance, streaming support.

**[Documentation](https://rubyclassifier.com/docs)** · **[Tutorials](https://rubyclassifier.com/docs/tutorials)** · **[API Reference](https://rubyclassifier.com/docs/api)**

## Why This Library?

| | This Gem | Other Forks |
|:--|:--|:--|
| **Algorithms** | 5 classifiers | 2 only |
| **Incremental LSI** | Brand's algorithm (no rebuild) | Full SVD rebuild on every add |
| **LSI Performance** | Native C extension (5-50x faster) | Pure Ruby or requires GSL |
| **Streaming** | Train on multi-GB datasets | Must load all data in memory |
| **Persistence** | Pluggable (file, Redis, S3) | Marshal only |

## Installation

```ruby
gem 'classifier'
```

## Quick Start

### Bayesian

```ruby
classifier = Classifier::Bayes.new(:spam, :ham)
classifier.train(spam: "Buy cheap viagra now!", ham: "Meeting at 3pm tomorrow")
classifier.classify "You've won a prize!"  # => "Spam"
```
[Bayesian Guide →](https://rubyclassifier.com/docs/guides/bayes/basics)

### Logistic Regression

```ruby
classifier = Classifier::LogisticRegression.new(:positive, :negative)
classifier.train(positive: "Great product!", negative: "Terrible experience")
classifier.classify "Loved it!"  # => "Positive"
```
[Logistic Regression Guide →](https://rubyclassifier.com/docs/guides/logistic-regression/basics)

### LSI (Latent Semantic Indexing)

```ruby
lsi = Classifier::LSI.new
lsi.add(pets: "Dogs are loyal", tech: "Ruby is elegant")
lsi.classify "My puppy is playful"  # => "pets"
```
[LSI Guide →](https://rubyclassifier.com/docs/guides/lsi/basics)

### k-Nearest Neighbors

```ruby
knn = Classifier::KNN.new(k: 3)
knn.train(spam: "Free money!", ham: "Quarterly report attached")  # or knn.add()
knn.classify "Claim your prize"  # => "spam"
```
[k-Nearest Neighbors Guide →](https://rubyclassifier.com/docs/guides/knn/basics)

### TF-IDF

```ruby
tfidf = Classifier::TFIDF.new
tfidf.fit(["Dogs are pets", "Cats are independent"])
tfidf.transform("Dogs are loyal")  # => {:dog => 0.707, :loyal => 0.707}
```
[TF-IDF Guide →](https://rubyclassifier.com/docs/guides/tfidf/basics)

## Key Features

### Incremental LSI

Add documents without rebuilding the entire index—400x faster for streaming data:

```ruby
lsi = Classifier::LSI.new(incremental: true)
lsi.add(tech: ["Ruby is elegant", "Python is popular"])
lsi.build_index

# These use Brand's algorithm—no full rebuild
lsi.add(tech: "Go is fast")
lsi.add(tech: "Rust is safe")
```

[Learn more →](https://rubyclassifier.com/docs/guides/lsi/incremental)

### Persistence

```ruby
classifier.storage = Classifier::Storage::File.new(path: "model.json")
classifier.save

loaded = Classifier::Bayes.load(storage: classifier.storage)
```

[Learn more →](https://rubyclassifier.com/docs/guides/persistence)

### Streaming Training

```ruby
classifier.train_from_stream(:spam, File.open("spam_corpus.txt"))
```

[Learn more →](https://rubyclassifier.com/docs/guides/streaming)

## Performance

Native C extension provides 5-50x speedup for LSI operations:

| Documents | Speedup |
|-----------|---------|
| 10 | 25x |
| 20 | 50x |

```bash
rake benchmark:compare  # Run your own comparison
```

## Development

```bash
bundle install
rake compile  # Build native extension
rake test     # Run tests
```

## Authors

- **Lucas Carlson** - lucas@rufy.com
- **David Fayram II** - dfayram@gmail.com
- **Cameron McBride** - cameron.mcbride@gmail.com
- **Ivan Acosta-Rubio** - ivan@softwarecriollo.com

## License

[LGPL 2.1](LICENSE)
