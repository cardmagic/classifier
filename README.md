# Classifier

[![Gem Version](https://badge.fury.io/rb/classifier.svg)](https://badge.fury.io/rb/classifier)
[![CI](https://github.com/cardmagic/classifier/actions/workflows/ruby.yml/badge.svg)](https://github.com/cardmagic/classifier/actions/workflows/ruby.yml)
[![License: LGPL](https://img.shields.io/badge/License-LGPL_2.1-blue.svg)](https://opensource.org/licenses/LGPL-2.1)

Text classification in Ruby. Five algorithms, native performance, streaming support.

**[Documentation](https://rubyclassifier.com/docs)** · **[Tutorials](https://rubyclassifier.com/docs/tutorials)** · **[API Reference](https://rubydoc.info/gems/classifier)**

## Why This Library?

| | This Gem | Other Forks |
|:--|:--|:--|
| **Algorithms** | ✅ 5 classifiers | ❌ 2 only |
| **Incremental LSI** | ✅ Brand's algorithm (no rebuild) | ❌ Full SVD rebuild on every add |
| **LSI Performance** | ✅ Native C extension (5-50x faster) | ❌ Pure Ruby or requires GSL |
| **Streaming** | ✅ Train on multi-GB datasets | ❌ Must load all data in memory |
| **Persistence** | ✅ Pluggable (file, Redis, S3, SQL, Custom) | ❌ Marshal only |

## Installation

```ruby
gem 'classifier'
```

Or install via Homebrew for CLI-only usage:

```bash
brew install classifier
```

## Command Line

Classify text instantly with pre-trained models—no coding required:

```bash
# Detect spam
classifier -r sms-spam-filter "You won a free iPhone"
# => spam

# Analyze sentiment
classifier -r imdb-sentiment "This movie was absolutely amazing"
# => positive

# Detect emotions
classifier -r emotion-detection "I am so happy today"
# => joy

# List all available models
classifier models
```

Train your own model:

```bash
# Train from files
classifier train positive reviews/good/*.txt
classifier train negative reviews/bad/*.txt

# Classify new text
classifier "Great product, highly recommend"
# => positive
```

[CLI Guide →](https://rubyclassifier.com/docs/guides/cli/basics)

## Quick Start

### Bayesian

```ruby
classifier = Classifier::Bayes.new(:spam, :ham)
classifier.train(spam: "Buy viagra cheap pills now")
classifier.train(spam: "You won million dollars prize")
classifier.train(ham: ["Meeting tomorrow at 3pm", "Quarterly report attached"])
classifier.classify("Cheap pills!")  # => "Spam"
```
[Bayesian Guide →](https://rubyclassifier.com/docs/guides/bayes/basics)

### Logistic Regression

```ruby
classifier = Classifier::LogisticRegression.new(:positive, :negative)
classifier.train(positive: "love amazing great wonderful")
classifier.train(negative: "hate terrible awful bad")
classifier.classify("I love it!")  # => "Positive"
```
[Logistic Regression Guide →](https://rubyclassifier.com/docs/guides/logisticregression/basics)

### LSI (Latent Semantic Indexing)

```ruby
lsi = Classifier::LSI.new
lsi.add(dog: "dog puppy canine bark fetch", cat: "cat kitten feline meow purr")
lsi.classify("My puppy barks")  # => "dog"
```
[LSI Guide →](https://rubyclassifier.com/docs/guides/lsi/basics)

### k-Nearest Neighbors

```ruby
knn = Classifier::KNN.new(k: 3)
%w[laptop coding software developer programming].each { |w| knn.add(tech: w) }
%w[football basketball soccer goal team].each { |w| knn.add(sports: w) }
knn.classify("programming code")  # => "tech"
```
[k-Nearest Neighbors Guide →](https://rubyclassifier.com/docs/guides/knn/basics)

### TF-IDF

```ruby
tfidf = Classifier::TFIDF.new
tfidf.fit(["Ruby is great", "Python is great", "Ruby on Rails"])
tfidf.transform("Ruby programming")  # => {:rubi => 1.0}
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

[Learn more →](https://rubyclassifier.com/docs/guides/lsi/basics)

### Persistence

```ruby
classifier.storage = Classifier::Storage::File.new(path: "model.json")
classifier.save

loaded = Classifier::Bayes.load(storage: classifier.storage)
```

[Learn more →](https://rubyclassifier.com/docs/guides/persistence/basics)

### Streaming Training

```ruby
classifier.train_from_stream(:spam, File.open("spam_corpus.txt"))
```

[Learn more →](https://rubyclassifier.com/docs/tutorials/streaming-training)

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
