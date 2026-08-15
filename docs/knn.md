# k-Nearest Neighbors

`Classifier::KNN` classifies text by the categories of its nearest examples. It
shows which examples drove the answer, which makes it useful when you must
explain a result.

It builds on [LSI](lsi.md) for the similarity measure.

## Add examples and classify

```ruby
require "classifier"

knn = Classifier::KNN.new(k: 3)
%w[laptop coding software developer programming].each { |w| knn.add(tech: w) }
%w[football basketball soccer goal team].each { |w| knn.add(sports: w) }

knn.classify("programming code")
# => "tech"
```

`train` is an alias of `add`, so the call reads the same as Bayes:

```ruby
knn.train(tech: "compiler", sports: "referee")
```

## See the neighbors

```ruby
knn.classify_with_neighbors("programming code")
```

The result holds the winning category, the neighbors that voted, the vote
tally, and a confidence value:

```ruby
{
  category: "tech",
  neighbors: [
    { item: "programming", category: "tech", similarity: 0.9999999999999993 },
    { item: "coding",      category: "tech", similarity: 0.9999999999999992 },
    { item: "team",        category: "sports", similarity: 2.6e-16 }
  ],
  votes: { "tech" => 2.0, "sports" => 1.0 },
  confidence: 0.6666666666666666
}
```

`confidence` is the winning share of the votes.

## Choose k

`k` sets how many neighbors vote. It defaults to 5.

```ruby
knn = Classifier::KNN.new(k: 3)
knn.k          # => 3
knn.k = 5
```

A small `k` follows the data closely and reacts to noise. A large `k` smooths
the boundary. Keep `k` at or below the number of examples you added.

## Weighted voting

By default every neighbor casts an equal vote. Weighted voting scales each vote
by similarity, so a close neighbor counts for more:

```ruby
knn = Classifier::KNN.new(k: 5, weighted: true)
```

Set it later with `knn.weighted = true`.

## Inspect the model

```ruby
knn.categories                   # => ["tech", "sports"]
knn.items                        # every added example
knn.categories_for("programming")
knn.remove_item("programming")
```

## Save and load

```ruby
knn.save_to_file("model.json")
loaded = Classifier::KNN.load_from_file("model.json")
```

See [Persistence](persistence.md).
