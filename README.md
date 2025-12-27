# Classifier

[![Gem Version](https://badge.fury.io/rb/classifier.svg)](https://badge.fury.io/rb/classifier)
[![CI](https://github.com/cardmagic/classifier/actions/workflows/ruby.yml/badge.svg)](https://github.com/cardmagic/classifier/actions/workflows/ruby.yml)
[![License: LGPL](https://img.shields.io/badge/License-LGPL_2.1-blue.svg)](https://opensource.org/licenses/LGPL-2.1)

A Ruby library for text classification using Bayesian and Latent Semantic Indexing (LSI) algorithms.

## Table of Contents

- [Installation](#installation)
- [Bayesian Classifier](#bayesian-classifier)
- [LSI (Latent Semantic Indexing)](#lsi-latent-semantic-indexing)
- [Performance](#performance)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Installation

Add to your Gemfile:

```ruby
gem 'classifier'
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install classifier
```

### Optional: GSL for Faster LSI

For significantly faster LSI operations, install the [GNU Scientific Library](https://www.gnu.org/software/gsl/).

<details>
<summary><strong>Ruby 3+</strong></summary>

The released `gsl` gem doesn't support Ruby 3+. Install from source:

```bash
# Install GSL library
brew install gsl        # macOS
apt-get install libgsl-dev  # Ubuntu/Debian

# Build and install the gem
git clone https://github.com/cardmagic/rb-gsl.git
cd rb-gsl
git checkout fix/ruby-3.4-compatibility
gem build gsl.gemspec
gem install gsl-*.gem
```
</details>

<details>
<summary><strong>Ruby 2.x</strong></summary>

```bash
# macOS
brew install gsl
gem install gsl

# Ubuntu/Debian
apt-get install libgsl-dev
gem install gsl
```
</details>

When GSL is installed, Classifier automatically uses it. To suppress the GSL notice:

```bash
SUPPRESS_GSL_WARNING=true ruby your_script.rb
```

### Compatibility

| Ruby Version | Status |
|--------------|--------|
| 4.0          | Supported |
| 3.4          | Supported |
| 3.3          | Supported |
| 3.2          | Supported |
| 3.1          | EOL (unsupported) |

## Bayesian Classifier

Fast, accurate classification with modest memory requirements. Ideal for spam filtering, sentiment analysis, and content categorization.

### Quick Start

```ruby
require 'classifier'

classifier = Classifier::Bayes.new('Spam', 'Ham')

# Train the classifier
classifier.train_spam "Buy cheap viagra now! Limited offer!"
classifier.train_spam "You've won a million dollars! Claim now!"
classifier.train_ham "Meeting scheduled for tomorrow at 10am"
classifier.train_ham "Please review the attached document"

# Classify new text
classifier.classify "Congratulations! You've won a prize!"
# => "Spam"
```

### Persistence with Madeleine

```ruby
require 'classifier'
require 'madeleine'

m = SnapshotMadeleine.new("classifier_data") {
  Classifier::Bayes.new('Interesting', 'Uninteresting')
}

m.system.train_interesting "fascinating article about science"
m.system.train_uninteresting "boring repetitive content"
m.take_snapshot

# Later, restore and use:
m.system.classify "new scientific discovery"
# => "Interesting"
```

### Learn More

- [Bayesian Filtering Explained](http://www.process.com/precisemail/bayesian_filtering.htm)
- [Wikipedia: Bayesian Filtering](http://en.wikipedia.org/wiki/Bayesian_filtering)
- [Paul Graham: A Plan for Spam](http://www.paulgraham.com/spam.html)

## LSI (Latent Semantic Indexing)

Semantic analysis using Singular Value Decomposition (SVD). More flexible than Bayesian classifiers, providing search, clustering, and classification based on meaning rather than just keywords.

### Quick Start

```ruby
require 'classifier'

lsi = Classifier::LSI.new

# Add documents with categories
lsi.add_item "Dogs are loyal pets that love to play fetch", :pets
lsi.add_item "Cats are independent and love to nap", :pets
lsi.add_item "Ruby is a dynamic programming language", :programming
lsi.add_item "Python is great for data science", :programming

# Classify new text
lsi.classify "My puppy loves to run around"
# => :pets

# Get classification with confidence score
lsi.classify_with_confidence "Learning to code in Ruby"
# => [:programming, 0.89]
```

### Search and Discovery

```ruby
# Find similar documents
lsi.find_related "Dogs are great companions", 2
# => ["Dogs are loyal pets that love to play fetch", "Cats are independent..."]

# Search by keyword
lsi.search "programming", 3
# => ["Ruby is a dynamic programming language", "Python is great for..."]
```

### Learn More

- [Wikipedia: Latent Semantic Analysis](http://en.wikipedia.org/wiki/Latent_semantic_analysis)
- [C2 Wiki: Latent Semantic Indexing](http://www.c2.com/cgi/wiki?LatentSemanticIndexing)

## Performance

### GSL vs Native Ruby

GSL provides dramatic speedups for LSI operations, especially `build_index` (SVD computation):

| Documents | build_index | Overall |
|-----------|-------------|---------|
| 5         | 4x faster   | 2.5x    |
| 10        | 24x faster  | 5.5x    |
| 15        | 116x faster | 17x     |

<details>
<summary>Detailed benchmark (15 documents)</summary>

```
Operation              Native          GSL      Speedup
----------------------------------------------------------
build_index            0.1412       0.0012       116.2x
classify               0.0142       0.0049         2.9x
search                 0.0102       0.0026         3.9x
find_related           0.0069       0.0016         4.2x
----------------------------------------------------------
TOTAL                  0.1725       0.0104        16.6x
```
</details>

### Running Benchmarks

```bash
rake benchmark              # Run with current configuration
rake benchmark:compare      # Compare GSL vs native Ruby
```

## Development

### Setup

```bash
git clone https://github.com/cardmagic/classifier.git
cd classifier
bundle install
```

### Running Tests

```bash
rake test                        # Run all tests
ruby -Ilib test/bayes/bayesian_test.rb  # Run specific test file

# Test without GSL (pure Ruby)
NATIVE_VECTOR=true rake test
```

### Console

```bash
rake console
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -am 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Authors

- **Lucas Carlson** - *Original author* - lucas@rufy.com
- **David Fayram II** - *LSI implementation* - dfayram@gmail.com
- **Cameron McBride** - cameron.mcbride@gmail.com
- **Ivan Acosta-Rubio** - ivan@softwarecriollo.com

## License

This library is released under the [GNU Lesser General Public License (LGPL) 2.1](LICENSE).
