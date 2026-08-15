# Streaming

Streaming trains a classifier on data larger than memory. The reader pulls one
batch of lines at a time, so peak memory stays flat whatever the corpus size.

Each **line** is one document.

## Train from a stream

```ruby
require "classifier"

classifier = Classifier::Bayes.new(:spam, :ham)
classifier.train_from_stream(:spam, File.open("spam_corpus.txt"))
```

`Classifier::LogisticRegression` and `Classifier::KNN` accept the same call.
`Classifier::TFIDF` uses `fit_from_stream`, because it fits a vocabulary rather
than a category.

## Progress

Pass a block to watch the run:

```ruby
classifier.train_from_stream(:spam, File.open("spam_corpus.txt")) do |progress|
  puts "completed=#{progress.completed}"
end
```

`Classifier::Streaming::Progress` reports `completed`, and `total` when the
reader can estimate the line count from the file size.

## Batch size

The reader groups lines into batches. The default is
`Classifier::Streaming::DEFAULT_BATCH_SIZE`.

```ruby
classifier.train_from_stream(:spam, File.open("corpus.txt"), batch_size: 500)
```

A larger batch does less bookkeeping and uses more memory.

## Train from an array

`train_batch` takes documents already in memory and uses the same batching:

```ruby
classifier.train_batch(:spam, ["cheap pills", "you won a prize"])
```

`Classifier::LSI` and `Classifier::KNN` name the same method `add_batch`, which
matches their `add` API:

```ruby
lsi.add_batch(tech: ["Ruby is elegant", "Python is popular"])
```

## Read several files as one stream

`Classifier::Streaming::MultiIO` presents many sources as one sequential
stream. It accepts file paths, IO objects, or both:

```ruby
multi = Classifier::Streaming::MultiIO.new(["a.txt", "b.txt"])
multi.each_line { |line| puts line }
```

```ruby
Classifier::Streaming::MultiIO.new(Dir["corpus/*.txt"]).each_line.to_a
```

Given a path, `MultiIO` opens the file, reads it, and closes it before it moves
to the next one. Only one file is ever open, so a corpus larger than the file
descriptor limit still works. Given an IO object, it reads that object and
leaves the closing to you.

`each_line` returns an Enumerator when you pass no block.

Combine it with a vectorizer to fit a whole corpus:

```ruby
tfidf = Classifier::TFIDF.new
tfidf.fit_from_stream(
  Classifier::Streaming::MultiIO.new(Dir["corpus/*.txt"])
)
tfidf.num_documents
```

## Checkpoints

A long run writes checkpoints through the assigned storage backend, so a
failure does not cost the whole pass:

```ruby
classifier.storage = Classifier::Storage::File.new(path: "model.json")
resumed = Classifier::Bayes.load_checkpoint(
  storage: classifier.storage,
  checkpoint_id: "run-1"
)
```

See [Persistence](persistence.md) for the backends.
