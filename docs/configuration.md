# Configuration

## Global settings

`Classifier.configure` sets the defaults for every classifier:

```ruby
require "classifier"

Classifier.configure do |config|
  config.min_word_length = 2
end

Classifier.config.min_word_length
# => 2
```

| Setting | Default | Effect |
|:--|:--|:--|
| `min_word_length` | 3 | The tokenizer drops any word shorter than this |

Set the configuration once at startup. The lazy setup is not thread-safe, so do
not first touch it from several threads at once.

Every classifier also takes `min_word_length` on its own, which overrides the
global value:

```ruby
Classifier::Bayes.new(:spam, :ham, min_word_length: 2)
```

## Tokenization

The tokenizer downcases the text, strips punctuation, drops the stop words in
`CORPUS_SKIP_WORDS`, drops words shorter than `min_word_length`, and reduces
each remaining word to its Porter stem.

```ruby
"Ruby programming is elegant".word_hash
# => {rubi: 1, program: 1, eleg: 1}
```

`clean_word_hash` skips the punctuation strip when the text is already clean.
`stem_to_word_hash` maps each stem back to the most frequent original word:

```ruby
"Ruby programming is elegant and programming rocks".stem_to_word_hash
# => {rubi: "ruby", program: "programming", eleg: "elegant", rock: "rocks"}
```

## Native extension

LSI uses a C extension for its linear algebra. It has no external dependency
and builds during `gem install`. Pure Ruby runs when the extension is absent,
with the same results and less speed.

```ruby
Classifier::LSI.backend
# => :native
```

The value is `:native` or `:ruby`.

Force pure Ruby with an environment variable, which is useful to compare the
two:

```bash
NATIVE_VECTOR=true bundle exec rake test
```

Build the extension from a checkout:

```bash
bundle exec rake compile
```

Silence the startup notice about the missing extension:

```bash
SUPPRESS_LSI_WARNING=true
```

## Errors

Every error inherits from `Classifier::Error`.

| Error | Raised when |
|:--|:--|
| `Classifier::NotFittedError` | A model is used before its fit. Logistic regression and TF-IDF |
| `Classifier::UnsavedChangesError` | `reload!` would discard unsaved changes |
| `Classifier::StorageError` | A storage backend operation fails |

```ruby
begin
  classifier.classify("text")
rescue Classifier::NotFittedError
  classifier.fit
  retry
end
```
