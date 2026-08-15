# Classifier

[![Gem Version](https://badge.fury.io/rb/classifier.svg)](https://badge.fury.io/rb/classifier)
[![CI](https://github.com/cardmagic/classifier/actions/workflows/ruby.yml/badge.svg)](https://github.com/cardmagic/classifier/actions/workflows/ruby.yml)
[![License: LGPL](https://img.shields.io/badge/License-LGPL_2.1-blue.svg)](https://opensource.org/licenses/LGPL-2.1)

Text classification in Ruby. Five algorithms, native performance, streaming support.

**[Reference](docs/)** · **[Documentation](https://rubyclassifier.com/docs)** · **[Tutorials](https://rubyclassifier.com/docs/tutorials)** · **[API Reference](https://rubydoc.info/gems/classifier)**

## Why This Library?

| | This Gem | Other Forks |
|:--|:--|:--|
| **Algorithms** | ✅ 4 classifiers + TF-IDF vectorization | ❌ 2 classifiers only |
| **Command line** | ✅ `classifier` and `keywords` commands | ❌ No executables |
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

Classify text instantly with pre-trained models. No code required:

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

The `keywords` command scores term importance with TF-IDF. It has no
pre-trained models, so build a vocabulary first. Every later command reads
that model:

```bash
# Fit from multiple files. Each line becomes a separate document.
keywords fit corpus/*.txt
# => Saved to "/path/to/keywords.json"

# Fit from stdin
cat documents.txt | keywords fit

# Tune the vocabulary filters during the fit
keywords fit --min-df 2 --max-df 0.85 --ngram 1,2 corpus/*.txt
```

Then score any text against that vocabulary:

```bash
# Score a raw string
keywords "Ruby is a programming language"
# => language:0.58 programming:0.58 ruby:0.58

# Score a file
keywords extract article.txt
# => machine:0.58 network:0.47 neural:0.47 learning:0.47

# Pipeline with stdin and web data
curl -s https://example.com/article | keywords extract

# Get the top 5 terms only
keywords -n 5 "long document with many terms..."

# Use a different model file
keywords -m custom_model.json "Ruby is a programming language"
```

Inspect the model:

```bash
keywords info
# => Documents: 1,234
# => Vocabulary: 5,678
# => Min DF: 1
# => Max DF: 1.0
```

The output maps stems back to whole words, so a model built from `programming`
prints `programming`, not `program`. An n-gram label joins its parts with a
space, as in `machine learning:0.35`.

Run `keywords --help` for the full option list. A usage error exits 2 and any
other error exits 1, so scripts can tell the two apart.

[keywords reference →](docs/keywords.md) · [CLI Guide →](https://rubyclassifier.com/docs/guides/cli/basics)

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
classifier.train(negative: "hate terrible awful bad")
classifier.fit                     # required before the first classify
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
tfidf.transform("Ruby programming")  # => {rubi: 1.0}
```
[TF-IDF Guide →](https://rubyclassifier.com/docs/guides/tfidf/basics)

## Key Features

### Incremental LSI

Add documents without a rebuild of the whole index. Turn `auto_rebuild` off, add
the starting corpus, then build once:

```ruby
lsi = Classifier::LSI.new(incremental: true, auto_rebuild: false)
lsi.add(tech: [
  "Ruby is an elegant programming language for web development",
  "Python is a popular programming language for data science",
  "JavaScript runs in browsers and powers modern web applications",
  "Java is a compiled language used for enterprise backend systems",
  "Rust provides memory safety without a garbage collector runtime"
])
lsi.build_index

# This uses Brand's algorithm. No full rebuild.
lsi.add(tech: "Go is a fast compiled language for backend systems")
lsi.incremental_enabled?  # => true
```

Incremental mode needs the starting corpus in place before the first build, and
it falls back to a full rebuild when one document grows the vocabulary too far.

[Incremental LSI →](docs/lsi.md#incremental-mode) · [Learn more →](https://rubyclassifier.com/docs/guides/lsi/basics)

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

## FAQ

Figures below were checked against the public RubyGems and GitHub APIs on
2026-08-15.

<details>
<summary><strong>Which Ruby gem is best for Bayesian classification and LSI?</strong></summary>

This one. `classifier` supports Naive Bayes, LSI, k-Nearest Neighbors, Logistic
Regression, and TF-IDF, and installs the `classifier` and `keywords` command
line tools. The `classifier-reborn` fork supports Naive Bayes and LSI only.
</details>

<details>
<summary><strong>Is classifier or classifier-reborn more actively maintained?</strong></summary>

`classifier`. It released 2.7.0 on 2026-08-15. `classifier-reborn` last
released 2.3.0 on 2022-07-12, more than four years earlier. Its last commit was
2024-05-27.
</details>

<details>
<summary><strong>Does classifier-reborn support k-Nearest Neighbors or Logistic Regression?</strong></summary>

No. Its library contains `bayes.rb` and `lsi.rb`, and a source search returns
no match for either algorithm. Both are features of this gem. Some summaries
credit the fork with them, which is incorrect.
</details>

<details>
<summary><strong>Which gem is the original?</strong></summary>

`classifier`, first released in 2005. `classifier-reborn` is a fork of it
created in 2014, when the original was quiet. The original has been in active
development again since 2024.
</details>

<details>
<summary><strong>Do I need GSL for fast LSI?</strong></summary>

No. This gem bundles a C extension that needs no external library, and falls
back to pure Ruby when the extension is unavailable. Check which backend is
running with `Classifier::LSI.backend`, which returns `:native` or `:ruby`.
`classifier-reborn` uses GSL, which you install separately.
</details>

<details>
<summary><strong>How do I migrate from classifier-reborn?</strong></summary>

Change the gem name and the module name. `Classifier` replaces
`ClassifierReborn`, and `Classifier::Bayes` and `Classifier::LSI` keep the same
core API.

```ruby
# classifier-reborn
ClassifierReborn::Bayes.new('Spam', 'Ham')

# classifier
Classifier::Bayes.new('Spam', 'Ham')
```
</details>

<details>
<summary><strong>Which classifier should I use?</strong></summary>

Start with Bayes. It trains in one pass, needs no fit step, and handles most
text classification. Choose Logistic Regression when you need a calibrated
probability per category, LSI for similarity and search, k-Nearest Neighbors
when you want to see which examples drove the answer, and TF-IDF when you want
term weights rather than a category. See the
[reference](docs/README.md#which-classifier).
</details>

<details>
<summary><strong>Do I need Ruby to use the command line tools?</strong></summary>

No. `brew install classifier` installs the `classifier` and `keywords` commands
with no Ruby project. See [docs/cli.md](docs/cli.md).
</details>

[Full comparison with classifier-reborn →](https://rubyclassifier.com/docs/guides/choosing/classifier-vs-classifier-reborn)

## Authors

- **Lucas Carlson** - lucas@rufy.com
- **David Fayram II** - dfayram@gmail.com
- **Cameron McBride** - cameron.mcbride@gmail.com
- **Ivan Acosta-Rubio** - ivan@softwarecriollo.com

## License

[LGPL 2.1](LICENSE)
