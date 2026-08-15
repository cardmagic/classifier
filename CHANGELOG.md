# Changelog

## 2.7.0 - 2026-08-15

- Add a `keywords` executable for TF-IDF keyword extraction. `keywords fit`
  builds a vocabulary from files or standard input, `keywords extract` reads a
  file, `keywords info` prints model statistics, and a bare text argument
  transforms that text. The command prints `term:score` pairs and maps stems
  back to whole words, so `keywords "Ruby is elegant"` prints
  `elegant:0.61 ruby:0.61`. Options set the model path, the top-N terms, quiet
  mode, `--min-df`, `--max-df`, and `--ngram`. Usage errors exit 2 and other
  errors exit 1. The gem now installs two executables, `classifier` and
  `keywords`.
- Treat each line as a separate document during `keywords fit`. The document
  count controls the inverse document frequency, so a file with many lines
  contributes many documents.
- Add `Classifier::Streaming::MultiIO`. It reads several IO objects or file
  paths as one sequential stream. It opens and closes each path one at a time,
  so a corpus larger than the file descriptor limit still fits.
- Add `String#stem_to_word_hash`. It maps each stemmed root to the most
  frequent original word in the text.
- Add the `min_df` and `max_df` readers to `Classifier::TFIDF`.
- Accept a `MultiIO` in `TFIDF#fit_from_stream` and `Streaming::LineReader`.

## 2.6.0 - 2026-06-25

- Add a `--search` flag to the command line tool to filter local models.
- Add a model detail view to the command line tool.
- Read model information in advance when the tool lists local models.

## 2.5.0 - 2026-06-01

- Accept keyword arguments in `train_from_stream`.

## 2.4.0 - 2026-05-19

- Make `min_word_length` configurable, so a caller can keep or drop short
  words during tokenization.
- Add a Claude Code plugin with a skill and slash commands.

## 2.3.2 - 2026-01-01

- Force UTF-8 encoding on the HTTP response body, so a remote model loads
  under any locale.

## 2.3.1 - 2026-01-01

- Force UTF-8 encoding when the locale is not UTF-8. Model data and user input
  no longer raise an encoding error.

## 2.3.0 - 2025-12-31

- Add a `classifier` executable with a model registry. The tool trains,
  classifies, and manages saved models from the shell.
- Fix the examples and the broken links in the README.
- Add Dependabot for automated dependency updates.

## 2.2.0 - 2025-12-29

- **Breaking:** set `required_ruby_version` to `>= 3.1`. Older Ruby versions
  are no longer supported.
- Add a k-Nearest Neighbors classifier.
- Add a Logistic Regression classifier.
- Add a TF-IDF vectorizer.
- Add streaming training and incremental SVD, so a corpus larger than memory
  can train a model.
- Add a hash-style API to add items to LSI.
- Add keyword arguments to `Bayes#train` and `Bayes#untrain`.
- Accept an array of categories in the classifier constructor.
- Fix the sentence and paragraph splits in `Summary`.
- Add property-based tests for the probabilistic invariants.

## 2.1.0 - 2025-12-28

- Replace the optional GSL dependency with a bundled C extension for LSI. The
  extension has no external dependency and falls back to pure Ruby.
- Add pluggable persistence backends through a storage API.
- Add `save` and `load` methods for classifier persistence.
- Add thread safety to the Bayes and LSI classifiers.
- Expose the LSI tuning parameters, with validation and an introspection API.
- Cache the expensive computations in the Bayes classifier.

## 2.0.0 - 2025-12-27

- **Breaking:** replace the fixed 0.1 constant in the Bayes classifier with
  add-one (Laplace) smoothing, where
  `P(word|category) = (count + 1) / (total + vocabulary_size)`. The smoothing
  now scales with the vocabulary size and applies to seen and unseen words
  alike. Classification scores change as a result.
- Fix an LSI dimension mismatch in the pure Ruby SVD.
- Fix the numerical stability of the SVD implementation.
- Replace the separate RBS files with inline annotations.
- Add a GitHub Actions workflow that publishes the gem on a version tag.
- Add an LSI benchmark that compares GSL against pure Ruby.
- Add RuboCop and SimpleCov.

## 1.4.4 - 2024-07-31

- Improve the scaling of the LSI content node.

## 1.4.3 - 2024-07-31

- Require `set` and use the explicit `::Set` namespace.
- Refactor `prepare_category_name`.

## 1.4.2 - 2024-07-31

- Fix the word count when `remove_category` runs.
- Add the `mutex_m` dependency and update the `fast-stemmer` version.

## 1.4.1 - 2024-07-31

- Add `remove_category` to the Bayes classifier.

## 1.4.0 - 2024-07-31

- Add `classify_with_confidence` to the LSI classifier.
- Require `mathn` only for Ruby 2.5 and later, and add `cmath` for Ruby 2.7
  and later.
- Silence the warnings about an uninitialized `$GSL`, and correct the rb-gsl
  URL hint.
- Package the test files in the gem.
- Add a Gemfile.lock.

## 1.3.5 - 2018-04-17

- Use Minitest for the test suite.
- Add the `mathn` dependency, which Ruby 2.5.0 removed.
- Make the gem installable through Bundler and a git remote.
- Fix the gemspec and the unit tests.

## 1.3.4 - 2013-12-31

- Use a prior in the Bayes classifier.
- Change the skip word list from an array to a set.
- Reduce the number of regular expression matches during tokenization.
- Stem only the words that the tokenizer keeps.
- Default the word hash values to 0.
- Add a gemspec, a README, and Travis CI.

## 1.3.3 - 2010-07-06

- Use fast-stemmer for the Porter stemmer.
- Check `$GSL` before a call to `Matrix.diag`, so the code uses `GSL::Matrix`.

## 1.3.2 - 2010-07-06

- Fix the reported issue #1.

## 1.3.1 and earlier

Versions 1.0 through 1.3.1 reached RubyGems on 2009-07-25. The git history
before 2010 is too sparse to attribute each change to one of these versions.
