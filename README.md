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
brew install cardmagic/tap/classifier
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

### Claude Code Plugin

Install as a plugin to get skills (auto-invoked) and slash commands:

```bash
# Add the marketplace
claude plugin marketplace add cardmagic/ai-marketplace

# Install the plugin
claude plugin install classifier@cardmagic
```

This gives you:
- **Skill**: Claude automatically classifies text when you ask about spam, sentiment, or emotions
- **Slash commands**: `/classifier:classify`, `/classifier:train`, `/classifier:models`

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
classifier.train(negative: "hate terrible

## Contributing

We welcome contributions! To get started:
1. Fork the repository and create your feature branch.
2. Run `bundle install` to install dependencies.
3. Ensure all tests pass by running `rake test`.
4. Submit a Pull Request with a clear description of your changes.

## License

This library is released under the [LGPL-2.1 License](https://opensource.org/licenses/LGPL-2.1).