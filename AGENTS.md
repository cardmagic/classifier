# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

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

## Changelog

`CHANGELOG.md` records every user-visible change. Add an entry in the same pull
request that makes the change. A reviewer who finds a behavior change without an
entry asks for one.

Write entries for the person who installs the gem, not for the person who wrote
the commit:

- Describe the behavior that ships, not the path taken to reach it. A bug that a
  reviewer found and the author fixed before release never existed for a user.
- Put the entry under a `## X.Y.Z - YYYY-MM-DD` heading. Use the released
  version number without a `v` prefix, and an ISO date.
- Start a breaking change with `**Breaking:**` and say what a caller must now
  do differently.
- Name the public constant, method, or command that changed, and show the
  command or call when an example makes it concrete.
- Skip changes a user cannot observe: dependency bumps for development, lint
  configuration, CI, and internal refactors.
- Order the entries within a release by how much they matter to a user.

Choose the version with semantic versioning: a breaking change is a major, a new
feature is a minor, and a fix alone is a patch.

## Release Workflow

Update `lib/classifier/version.rb`, `CHANGELOG.md`, and `Gemfile.lock`. Run
`bundle exec rake` and `bundle exec rubocop`. Then commit and merge to `master`.

Publish by pushing an annotated version tag:

```bash
git tag -a v2.7.0 -m "Version 2.7.0"
git push origin v2.7.0
```

The `Release` workflow runs CI, builds the gem, publishes it through RubyGems
trusted publishing, and creates the GitHub release. Never run `gem push` from a
workstation.

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
