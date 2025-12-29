# Classifier

[![Gem Version](https://badge.fury.io/rb/classifier.svg)](https://badge.fury.io/rb/classifier)
[![CI](https://github.com/cardmagic/classifier/actions/workflows/ruby.yml/badge.svg)](https://github.com/cardmagic/classifier/actions/workflows/ruby.yml)
[![License: LGPL](https://img.shields.io/badge/License-LGPL_2.1-blue.svg)](https://opensource.org/licenses/LGPL-2.1)

A Ruby library for text classification using Bayesian, LSI (Latent Semantic Indexing), and k-Nearest Neighbors (kNN) algorithms.

**[Documentation](https://rubyclassifier.com/docs)** · **[Tutorials](https://rubyclassifier.com/docs/tutorials)** · **[Guides](https://rubyclassifier.com/docs/guides)**

## Table of Contents

- [Installation](#installation)
- [Bayesian Classifier](#bayesian-classifier)
- [LSI (Latent Semantic Indexing)](#lsi-latent-semantic-indexing)
- [k-Nearest Neighbors (kNN)](#k-nearest-neighbors-knn)
- [Persistence](#persistence)
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

### Native C Extension

The gem includes a native C extension for fast LSI operations. It compiles automatically during gem installation. No external dependencies are required.

To verify the native extension is active:

```ruby
require 'classifier'
puts Classifier::LSI.backend  # => :native
```

To force pure Ruby mode (for debugging):

```bash
NATIVE_VECTOR=true ruby your_script.rb
```

To suppress the warning when native extension isn't available:

```bash
SUPPRESS_LSI_WARNING=true ruby your_script.rb
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

classifier = Classifier::Bayes.new(:spam, :ham)

# Train with keyword arguments
classifier.train(spam: "Buy cheap viagra now! Limited offer!")
classifier.train(ham: "Meeting scheduled for tomorrow at 10am")

# Train multiple items at once
classifier.train(
  spam: ["You've won a million dollars!", "Free money!!!"],
  ham: ["Please review the document", "Lunch tomorrow?"]
)

# Classify new text
classifier.classify "Congratulations! You've won a prize!"
# => "Spam"
```

### Learn More

- [Bayes Basics Guide](https://rubyclassifier.com/docs/guides/bayes/basics) - In-depth documentation
- [Build a Spam Filter Tutorial](https://rubyclassifier.com/docs/tutorials/spam-filter) - Step-by-step guide
- [Paul Graham: A Plan for Spam](http://www.paulgraham.com/spam.html)

## LSI (Latent Semantic Indexing)

Semantic analysis using Singular Value Decomposition (SVD). More flexible than Bayesian classifiers, providing search, clustering, and classification based on meaning rather than just keywords.

### Quick Start

```ruby
require 'classifier'

lsi = Classifier::LSI.new

# Add documents with hash-style syntax (category => item(s))
lsi.add("Pets" => "Dogs are loyal pets that love to play fetch")
lsi.add("Pets" => "Cats are independent and love to nap")
lsi.add("Programming" => "Ruby is a dynamic programming language")

# Add multiple items with the same category
lsi.add("Programming" => ["Python is great for data science", "JavaScript runs in browsers"])

# Batch operations with multiple categories
lsi.add(
  "Pets" => ["Hamsters are small furry pets", "Birds can be great companions"],
  "Programming" => "Go is fast and concurrent"
)

# Classify new text
lsi.classify "My puppy loves to run around"
# => "Pets"

# Get classification with confidence score
lsi.classify_with_confidence "Learning to code in Ruby"
# => ["Programming", 0.89]
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

### Text Summarization

LSI can extract key sentences from text:

```ruby
text = "First sentence about dogs. Second about cats. Third about birds."
text.summary(2)  # Extract 2 most relevant sentences
```

For better sentence boundary detection (handles abbreviations like "Dr.", decimals, etc.), install the optional `pragmatic_segmenter` gem:

```ruby
gem 'pragmatic_segmenter'
```

### Learn More

- [LSI Basics Guide](https://rubyclassifier.com/docs/guides/lsi/basics) - In-depth documentation
- [Wikipedia: Latent Semantic Analysis](http://en.wikipedia.org/wiki/Latent_semantic_analysis)

## k-Nearest Neighbors (kNN)

Instance-based classification that stores examples and classifies by finding the most similar ones. No training phase required—just add examples and classify.

### Key Features

- **No Training Required**: Uses instance-based learning—store examples and classify by similarity
- **Interpretable Results**: Returns neighbors that contributed to the decision
- **Incremental Updates**: Easy to add or remove examples without retraining
- **Distance-Weighted Voting**: Optional weighting by similarity score
- **Built on LSI**: Leverages LSI's semantic similarity for better matching

### Quick Start

```ruby
require 'classifier'

knn = Classifier::KNN.new(k: 3)

# Add labeled examples
knn.add(spam: ["Buy now! Limited offer!", "You've won a million dollars!"])
knn.add(ham: ["Meeting at 3pm tomorrow", "Please review the document"])

# Classify new text
knn.classify "Congratulations! Claim your prize!"
# => "spam"
```

### Detailed Classification

Get neighbor information for interpretable results:

```ruby
result = knn.classify_with_neighbors "Free money offer"

result[:category]    # => "spam"
result[:confidence]  # => 0.85
result[:neighbors]   # => [{item: "Buy now!...", category: "spam", similarity: 0.92}, ...]
result[:votes]       # => {"spam" => 2.0, "ham" => 1.0}
```

### Distance-Weighted Voting

Weight votes by similarity score for more accurate classification:

```ruby
knn = Classifier::KNN.new(k: 5, weighted: true)

knn.add(
  positive: ["Great product!", "Loved it!", "Excellent service"],
  negative: ["Terrible experience", "Would not recommend"]
)

# Closer neighbors have more influence on the result
knn.classify "This was amazing!"
# => "positive"
```

### Updating the Classifier

```ruby
# Add more examples anytime
knn.add(neutral: "It was okay, nothing special")

# Remove examples
knn.remove_item "Buy now! Limited offer!"

# Change k value
knn.k = 7

# List all categories
knn.categories
# => ["spam", "ham", "neutral"]
```

### When to Use kNN vs Bayes vs LSI

| Classifier | Best For |
|------------|----------|
| **Bayes** | Large training sets, fast classification, spam filtering |
| **LSI** | Semantic similarity, document clustering, search |
| **kNN** | Small datasets, interpretable results, incremental learning |

## Persistence

Save and load classifiers with pluggable storage backends. Works with Bayes, LSI, and kNN classifiers.

### File Storage

```ruby
require 'classifier'

classifier = Classifier::Bayes.new(:spam, :ham)
classifier.train(spam: "Buy now! Limited offer!")
classifier.train(ham: "Meeting tomorrow at 3pm")

# Configure storage and save
classifier.storage = Classifier::Storage::File.new(path: "spam_filter.json")
classifier.save

# Load later
loaded = Classifier::Bayes.load(storage: classifier.storage)
loaded.classify "Claim your prize now!"
# => "Spam"
```

### Custom Storage Backends

Create backends for Redis, PostgreSQL, S3, or any storage system:

```ruby
class RedisStorage < Classifier::Storage::Base
  def initialize(redis:, key:)
    super()
    @redis, @key = redis, key
  end

  def write(data) = @redis.set(@key, data)
  def read = @redis.get(@key)
  def delete = @redis.del(@key)
  def exists? = @redis.exists?(@key)
end

# Use it
classifier.storage = RedisStorage.new(redis: Redis.new, key: "classifier:spam")
classifier.save
```

### Learn More

- [Persistence Guide](https://rubyclassifier.com/docs/guides/persistence/basics) - Full documentation with examples

## Performance

### Native C Extension vs Pure Ruby

The native C extension provides dramatic speedups for LSI operations, especially `build_index` (SVD computation):

| Documents | build_index | Overall |
|-----------|-------------|---------|
| 5         | 7x faster   | 2.6x    |
| 10        | 25x faster  | 4.6x    |
| 15        | 112x faster | 14.5x   |
| 20        | 385x faster | 48.7x   |

<details>
<summary>Detailed benchmark (20 documents)</summary>

```
Operation            Pure Ruby     Native C      Speedup
----------------------------------------------------------
build_index            0.5540       0.0014       384.5x
classify               0.0190       0.0060         3.2x
search                 0.0145       0.0037         3.9x
find_related           0.0098       0.0011         8.6x
----------------------------------------------------------
TOTAL                  0.5973       0.0123        48.7x
```
</details>

### Running Benchmarks

```bash
rake benchmark              # Run with current configuration
rake benchmark:compare      # Compare native C vs pure Ruby
```

## Development

### Setup

```bash
git clone https://github.com/cardmagic/classifier.git
cd classifier
bundle install
rake compile  # Compile native C extension
```

### Running Tests

```bash
rake test                        # Run all tests (compiles first)
ruby -Ilib test/bayes/bayesian_test.rb  # Run specific test file

# Test with pure Ruby (no native extension)
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
