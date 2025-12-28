# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ruby gem providing text classification via two algorithms:
- **Bayes** (`Classifier::Bayes`) - Naive Bayesian classification
- **LSI** (`Classifier::LSI`) - Latent Semantic Indexing for semantic classification, clustering, and search

## Common Commands

```bash
# Compile native C extension
bundle exec rake compile

# Run all tests (compiles first)
bundle exec rake test

# Run a single test file
ruby -Ilib test/bayes/bayesian_test.rb
ruby -Ilib test/lsi/lsi_test.rb

# Run tests with pure Ruby (no native extension)
NATIVE_VECTOR=true bundle exec rake test

# Run benchmarks
bundle exec rake benchmark
bundle exec rake benchmark:compare

# Interactive console
bundle exec rake console

# Generate documentation
bundle exec rake doc
```

## Architecture

### Core Components

**Bayesian Classifier** (`lib/classifier/bayes.rb`)
- Train with `train(category, text)` or dynamic methods like `train_spam(text)`
- Classify with `classify(text)` returning the best category
- Uses log probabilities for numerical stability

**LSI Classifier** (`lib/classifier/lsi.rb`)
- Uses Singular Value Decomposition (SVD) for semantic analysis
- Native C extension for 5-50x faster matrix operations; falls back to pure Ruby
- Key operations: `add_item`, `classify`, `find_related`, `search`
- `auto_rebuild` option controls automatic index rebuilding after changes

**String Extensions** (`lib/classifier/extensions/word_hash.rb`)
- `word_hash` / `clean_word_hash` - tokenize text to stemmed word frequencies
- `CORPUS_SKIP_WORDS` - stopwords filtered during tokenization
- Uses `fast-stemmer` gem for Porter stemming

**Vector Extensions** (`lib/classifier/extensions/vector.rb`)
- Pure Ruby SVD implementation (`Matrix#SV_decomp`) - used as fallback
- Vector normalization and magnitude calculations

### Native C Extension (`ext/classifier/`)

LSI uses a native C extension for fast linear algebra operations:
- `Classifier::Linalg::Vector` - Vector operations (alloc, normalize, dot product)
- `Classifier::Linalg::Matrix` - Matrix operations (alloc, transpose, multiply)
- Jacobi SVD implementation for singular value decomposition

Check current backend: `Classifier::LSI.backend` returns `:native` or `:ruby`
Force pure Ruby: `NATIVE_VECTOR=true bundle exec rake test`

### Content Nodes (`lib/classifier/lsi/content_node.rb`)

Internal data structure storing:
- `word_hash` - term frequencies
- `raw_vector` / `raw_norm` - initial vector representation
- `lsi_vector` / `lsi_norm` - reduced dimensionality representation after SVD
