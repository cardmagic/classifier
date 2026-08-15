# LSI

`Classifier::LSI` implements Latent Semantic Indexing. It finds documents that
share meaning, not only shared words, so it answers similarity, search, and
related-document questions that a word-count classifier cannot.

It uses Singular Value Decomposition. A [native C extension](configuration.md)
makes that 5 to 50 times faster, and pure Ruby runs when the extension is
absent.

## Classify

```ruby
require "classifier"

lsi = Classifier::LSI.new
lsi.add(dog: "dog puppy canine bark fetch", cat: "cat kitten feline meow purr")

lsi.classify("My puppy barks")
# => "dog"
```

## Confidence

```ruby
lsi.classify_with_confidence("My puppy barks")
# => ["dog", 1.0]
```

The second value runs from 0.0 to 1.0.

## Search

```ruby
lsi.search("puppy", 2)
# => ["dog puppy canine bark fetch", "cat kitten feline meow purr"]
```

The second argument caps the result count. Results come back in descending
order of similarity.

## Related documents

```ruby
lsi.find_related("dog puppy canine bark fetch", 1)
```

## Add documents

`add` takes categories as keywords:

```ruby
lsi.add(dog: "dog puppy canine bark fetch")
lsi.add(tech: ["Ruby is elegant", "Python is popular"])
```

`add_item` takes the item first, then its categories, and accepts a block that
converts the item to text:

```ruby
lsi.add_item("dog puppy canine", :dog)
lsi.add_item(article, :tech) { |a| a.body }
```

## The index

LSI builds an index before it answers a query. By default it rebuilds whenever
it needs to. Turn that off to add many documents and rebuild once:

```ruby
lsi = Classifier::LSI.new(auto_rebuild: false)
lsi.add(dog: "dog puppy canine bark fetch")
lsi.add(cat: "cat kitten feline meow purr")
lsi.build_index
```

```ruby
lsi.needs_rebuild?
# => false
```

## Incremental mode

Incremental mode adds documents through Brand's algorithm, with no full
rebuild.

Turn `auto_rebuild` off. Incremental mode needs the whole starting corpus in
place before the first index build:

```ruby
lsi = Classifier::LSI.new(incremental: true, auto_rebuild: false, max_rank: 100)
lsi.add(tech: [
  "Ruby is an elegant programming language for web development",
  "Python is a popular programming language for data science",
  "JavaScript runs in browsers and powers modern web applications",
  "Java is a compiled language used for enterprise backend systems",
  "Rust provides memory safety without a garbage collector runtime"
])
lsi.build_index

lsi.incremental_enabled?
# => true

lsi.add(tech: "Go is a fast compiled language for backend systems")
lsi.incremental_enabled?
# => true
```

`build_index` stores the U matrix that later updates need. It stores that
matrix only while incremental mode is on.

**Leave `auto_rebuild` at its default and incremental mode never starts.** Each
`add` rebuilds at once, so the index builds from the first two documents, and
the next `add` measures its vocabulary growth against that tiny start. The
growth trips the threshold below, incremental mode switches off, and a later
`build_index` cannot turn it back on.

### The fallback

An added document that grows the vocabulary by more than 20 percent of its
size at the first build is too large a shift for an incremental update. LSI
then turns incremental mode off and rebuilds in full. The results stay correct.
The speed advantage stops.

The fallback is permanent. Call `enable_incremental_mode!` to resume:

```ruby
lsi.enable_incremental_mode!(max_rank: 100)
lsi.build_index(force: true)
```

`current_rank` reports the count of positive singular values.
`disable_incremental_mode!` turns the mode off by hand.

A corpus of a few documents grows its vocabulary quickly, so incremental mode
suits a large starting corpus and small later additions.

## Inspect the model

```ruby
lsi.items          # every indexed document
lsi.categories_for("dog puppy canine bark fetch")
lsi.remove_item("dog puppy canine bark fetch")
```

`singular_values` returns the raw values after `build_index`, and
`singular_value_spectrum` returns the variance each dimension explains.

`highest_ranked_stems` names the stems that carry a document:

```ruby
lsi.highest_ranked_stems("dog puppy canine bark fetch loyal", 3)
# => [:dog, :puppi, :canin]
```

The document must already be indexed, or the call raises.

`highest_relative_content` returns the documents nearest the center of the
whole set, which describes what a corpus is mostly about:

```ruby
lsi.highest_relative_content(2)
```

It returns an empty array while the index still needs a rebuild.

## Add without categories

`<<` indexes a document with no category, for search and similarity only:

```ruby
lsi << "bird sparrow robin fly nest feather"
```

## Add in batches

`add_batch` turns `auto_rebuild` off for the run, adds everything, then builds
once. It reports progress like the streaming API:

```ruby
lsi.add_batch(
  tech: ["Ruby is elegant", "Python is popular"],
  sports: ["soccer goal", "basketball hoop"]
) { |progress| puts progress.completed }
```

See [Streaming](streaming.md).

## Summaries

The gem adds `summary` to `String`:

```ruby
text = "The dog barks loudly. The cat sleeps quietly. " \
       "Birds sing sweetly in the morning light."

text.summary(1)
# => "The cat sleeps quietly."
```

The argument sets how many sentences come back.

## Constructor options

| Option | Default | Meaning |
|:--|:--|:--|
| `auto_rebuild` | `true` | Rebuild the index automatically after a change |
| `incremental` | `false` | Use Brand's algorithm to add documents |
| `max_rank` | 100 | Rank cap in incremental mode |
| `min_word_length` | 3 | Drop words shorter than this |

## Save and load

```ruby
lsi.save_to_file("model.json")
loaded = Classifier::LSI.load_from_file("model.json")
```

See [Persistence](persistence.md).
