# TF-IDF

`Classifier::TFIDF` turns text into term weights. It answers "which terms matter
in this document", not "which category is this". For the same thing from a
shell, use [`keywords`](keywords.md).

TF-IDF raises the weight of a term that is frequent in one document, and lowers
it for a term that is common across every document.

## Fit and transform

```ruby
require "classifier"

tfidf = Classifier::TFIDF.new
tfidf.fit(["Ruby is great", "Python is great", "Ruby on Rails"])

tfidf.transform("Ruby programming")
# => {rubi: 1.0}
```

The keys are Porter stems. `fit_transform` does both steps at once:

```ruby
tfidf.fit_transform(["Ruby is great", "Python is great"])
```

`transform` raises `Classifier::NotFittedError` before a fit.

## The vocabulary

```ruby
tfidf.feature_names   # every term in the vocabulary
tfidf.vocabulary      # term => column index
tfidf.idf             # term => inverse document frequency
tfidf.num_documents   # documents seen during the fit
tfidf.fitted?         # => true
```

## Document frequency filters

`min_df` and `max_df` drop terms that are too rare or too common.

```ruby
tfidf = Classifier::TFIDF.new(min_df: 2, max_df: 0.85)
```

| Parameter | Type | Meaning |
|:--|:--|:--|
| `min_df` | Integer | Keep a term only when at least this many documents hold it |
| `min_df` | Float | The same, as a ratio of the document count |
| `max_df` | Float | Drop a term that appears in more than this ratio of documents |
| `max_df` | Integer | The same, as an absolute document count |

An Integer means a count and a Float means a ratio. A Float must fall between
0.0 and 1.0, and an Integer must not be negative.

Both values are readable after construction, and a saved model keeps them:

```ruby
tfidf.min_df   # => 2
tfidf.max_df   # => 0.85
```

## N-grams

`ngram_range` sets the shortest and longest phrase to index. It defaults to
`[1, 1]`, which indexes single words only.

```ruby
tfidf = Classifier::TFIDF.new(ngram_range: [1, 2])
tfidf.fit(["machine learning rocks", "machine learning is fun"])

tfidf.feature_names.sort.first(6)
# => [:fun, :learn, :learn_fun, :learn_rock, :machin, :machin_learn]
```

An n-gram key joins its stems with an underscore. Both bounds must be 1 or
more, and the first must not exceed the second.

## Sublinear term frequency

`sublinear_tf: true` replaces the raw count with `1 + log(count)`, which damps
the effect of a term repeated many times in one document:

```ruby
tfidf = Classifier::TFIDF.new(sublinear_tf: true)
```

## Constructor

```ruby
Classifier::TFIDF.new(
  min_df: 1,
  max_df: 1.0,
  ngram_range: [1, 1],
  sublinear_tf: false,
  min_word_length: 3
)
```

## Fit from a stream

`fit_from_stream` reads line by line, so a corpus larger than memory still
fits. Each line is one document.

```ruby
tfidf = Classifier::TFIDF.new
tfidf.fit_from_stream(File.open("corpus.txt"))
```

Pass a [`MultiIO`](streaming.md) to read several files as one stream:

```ruby
tfidf.fit_from_stream(
  Classifier::Streaming::MultiIO.new(Dir["corpus/*.txt"])
)
```

## Map stems back to words

`transform` returns stems. `String#stem_to_word_hash` maps each stem back to the
most frequent original word, which is how `keywords` prints whole words:

```ruby
"Ruby programming is elegant and programming rocks".stem_to_word_hash
# => {rubi: "ruby", program: "programming", eleg: "elegant", rock: "rocks"}
```

## Save and load

```ruby
tfidf.save_to_file("vectorizer.json")
loaded = Classifier::TFIDF.load_from_file("vectorizer.json")
```

See [Persistence](persistence.md).
