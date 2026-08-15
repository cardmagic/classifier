# Bayes

`Classifier::Bayes` is a Naive Bayesian classifier. It trains in one pass, needs
no fit step, and suits most text classification tasks.

It uses log probabilities for numerical stability, and add-one (Laplace)
smoothing, where `P(word|category) = (count + 1) / (total + vocabulary_size)`.

## Train and classify

```ruby
require "classifier"

classifier = Classifier::Bayes.new(:spam, :ham)
classifier.train(spam: "Buy viagra cheap pills now")
classifier.train(spam: "You won million dollars prize")
classifier.train(ham: ["Meeting tomorrow at 3pm", "Quarterly report attached"])

classifier.classify("Cheap pills!")
# => "Spam"
```

A category name comes back capitalized. Pass an array to train several documents
against one category in a single call.

## Scores per category

```ruby
classifier.classifications("Cheap pills!")
# => {"Spam" => -8.579980179515003, "Ham" => -9.680344001221918}
```

These are log probabilities, so they are negative, and the highest value wins.

## Dynamic training methods

A `train_<category>` method exists for every category:

```ruby
classifier = Classifier::Bayes.new(:spam, :ham)
classifier.train_spam("cheap pills")
classifier.train_ham("meeting tomorrow")
classifier.classify("pills")
# => "Spam"
```

`untrain_<category>` removes a document the same way.

## Manage categories

```ruby
classifier.categories
# => ["Spam", "Ham"]

classifier.add_category(:other)
classifier.categories
# => ["Spam", "Ham", "Other"]

classifier.remove_category(:other)
classifier.categories
# => ["Spam", "Ham"]
```

`remove_category` also removes that category's word counts. `append_category` is
an alias of `add_category`.

## Untrain

```ruby
classifier.untrain(spam: "Buy viagra cheap pills now")
```

Untrain the same text you trained. A document you never trained corrupts the
counts.

## Short words

The tokenizer drops words shorter than `min_word_length`, which defaults to 3.
Raise or lower it per classifier:

```ruby
classifier = Classifier::Bayes.new(:spam, :ham, min_word_length: 2)
```

See [Configuration](configuration.md) to change the default for every
classifier.

## Constructor

```ruby
Classifier::Bayes.new(*categories, min_word_length: 3)
```

An array of categories also works:

```ruby
Classifier::Bayes.new([:spam, :ham])
```

## Save and load

```ruby
classifier.save_to_file("model.json")
loaded = Classifier::Bayes.load_from_file("model.json")
```

See [Persistence](persistence.md) for storage backends, and
[Streaming](streaming.md) for corpora larger than memory.
