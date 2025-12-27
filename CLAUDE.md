# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ruby gem providing text classification via two algorithms:
- **Bayes** (`Classifier::Bayes`) - Naive Bayesian classification
- **LSI** (`Classifier::LSI`) - Latent Semantic Indexing for semantic classification, clustering, and search

## Common Commands

```bash
# Run all tests
rake test

# Run a single test file
ruby -Ilib test/bayes/bayesian_test.rb
ruby -Ilib test/lsi/lsi_test.rb

# Run tests with native Ruby vector (without GSL)
NATIVE_VECTOR=true rake test

# Interactive console
rake console

# Generate documentation
rake doc
```

## Architecture

### Core Components

**Bayesian Classifier** (`lib/classifier/bayes.rb`)
- Train with `train(category, text)` or dynamic methods like `train_spam(text)`
- Classify with `classify(text)` returning the best category
- Uses log probabilities for numerical stability

**LSI Classifier** (`lib/classifier/lsi.rb`)
- Uses Singular Value Decomposition (SVD) for semantic analysis
- Optional GSL gem for 10x faster matrix operations; falls back to pure Ruby SVD
- Key operations: `add_item`, `classify`, `find_related`, `search`
- `auto_rebuild` option controls automatic index rebuilding after changes

**String Extensions** (`lib/classifier/extensions/word_hash.rb`)
- `word_hash` / `clean_word_hash` - tokenize text to stemmed word frequencies
- `CORPUS_SKIP_WORDS` - stopwords filtered during tokenization
- Uses `fast-stemmer` gem for Porter stemming

**Vector Extensions** (`lib/classifier/extensions/vector.rb`)
- Pure Ruby SVD implementation (`Matrix#SV_decomp`)
- Vector normalization and magnitude calculations

### GSL Integration

LSI checks for the `gsl` gem at load time. When available:
- Uses `GSL::Matrix` and `GSL::Vector` for faster operations
- Serialization handled via `vector_serialize.rb`
- Test without GSL: `NATIVE_VECTOR=true rake test`

### Content Nodes (`lib/classifier/lsi/content_node.rb`)

Internal data structure storing:
- `word_hash` - term frequencies
- `raw_vector` / `raw_norm` - initial vector representation
- `lsi_vector` / `lsi_norm` - reduced dimensionality representation after SVD
