# Persistence

Every classifier saves and loads the same way. `Classifier::Bayes`,
`Classifier::LogisticRegression`, `Classifier::LSI`, `Classifier::KNN`, and
`Classifier::TFIDF` all share this API.

## Files

```ruby
require "classifier"

classifier = Classifier::Bayes.new(:spam, :ham)
classifier.train(spam: "cheap pills", ham: "meeting tomorrow")

classifier.save_to_file("model.json")

loaded = Classifier::Bayes.load_from_file("model.json")
loaded.classify("pills")
# => "Spam"
```

The format is JSON, so a saved model is readable and portable between Ruby
versions.

## Storage backends

A backend separates the model from where it lives. Assign one, then call `save`
and `load` with no path:

```ruby
classifier.storage = Classifier::Storage::File.new(path: "model.json")
classifier.save

loaded = Classifier::Bayes.load(storage: classifier.storage)
```

The gem ships two backends:

| Backend | Use it for |
|:--|:--|
| `Classifier::Storage::File` | A model on disk |
| `Classifier::Storage::Memory` | Tests, and a model that lives for one process |

```ruby
storage = Classifier::Storage::Memory.new

classifier = Classifier::Bayes.new(:a, :b)
classifier.train(a: "alpha", b: "beta")
classifier.storage = storage
classifier.save

Classifier::Bayes.load(storage: storage).categories
# => ["A", "B"]
```

## Write your own backend

Subclass `Classifier::Storage::Base` and implement four methods:

```ruby
Classifier::Storage::Base.instance_methods(false).sort
# => [:delete, :exists?, :read, :write]
```

| Method | Contract |
|:--|:--|
| `write(key, data)` | Store the serialized model |
| `read(key)` | Return what `write` stored, or nil |
| `exists?(key)` | Report whether a model is stored under the key |
| `delete(key)` | Remove the stored model |

A Redis backend looks like this:

```ruby
class RedisStorage < Classifier::Storage::Base
  def initialize(redis:, namespace: "classifier")
    @redis = redis
    @namespace = namespace
  end

  def write(key, data) = @redis.set(namespaced(key), data)
  def read(key) = @redis.get(namespaced(key))
  def exists?(key) = @redis.exists?(namespaced(key))
  def delete(key) = @redis.del(namespaced(key))

  private

  def namespaced(key) = "#{@namespace}:#{key}"
end
```

The same shape covers S3, a SQL table, or any other store.

## Track unsaved changes

`dirty?` reports whether the model changed since the last save:

```ruby
classifier.dirty?
```

`reload` discards unsaved changes and reads the stored model again. `reload!`
does the same and raises when no stored model exists.

## Marshal

Every classifier also supports `Marshal`:

```ruby
data = Marshal.dump(classifier)
restored = Marshal.load(data)
```

Prefer JSON. Only load a marshalled model from a source you trust.

## Checkpoints

Streaming training writes checkpoints, so a long run resumes after a failure:

```ruby
Classifier::Bayes.load_checkpoint(storage: storage, checkpoint_id: "run-1")
```

See [Streaming](streaming.md).
