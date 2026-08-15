# Logistic Regression

`Classifier::LogisticRegression` is a linear classifier. It gives calibrated
probabilities that sum to 1.0, which Bayes does not.

## Train, fit, then classify

Unlike Bayes, this classifier needs a `fit` call after training. `classify`
raises `Classifier::NotFittedError` before that call.

```ruby
require "classifier"

classifier = Classifier::LogisticRegression.new(:positive, :negative)
classifier.train(positive: "love amazing great wonderful")
classifier.train(negative: "hate terrible awful bad")
classifier.fit

classifier.classify("I love it!")
# => "Positive"
```

Train more documents at any time. Call `fit` again before the next classify.

```ruby
classifier.fitted?
# => true
```

## Probabilities

```ruby
classifier.probabilities("I love it!")
# => {"Positive" => 0.7398506195705559, "Negative" => 0.26014938042944413}
```

The values sum to 1.0. Use `classifications` for the raw scores before the
sigmoid:

```ruby
classifier.classifications("I love it!")
# => {"Positive" => 0.5225961471158276, "Negative" => -0.5225961471158275}
```

## Inspect the weights

`weights` shows which terms drive a category:

```ruby
classifier.weights("positive")
# => {hate: -0.5225, terribl: -0.5225, aw: -0.5225, bad: -0.5225,
#     love: 0.5225, amaz: 0.5225, great: 0.5225, wonder: 0.5225}
```

The keys are Porter stems. The order runs by **absolute** value, so the terms
that matter most come first whichever way they point. A positive weight argues
for the category and a negative weight argues against it.

`limit` caps the count:

```ruby
classifier.weights("positive", limit: 3)
```

Terms of equal absolute weight tie, and a tie has no defined order. A toy
corpus like the one above gives every term the same magnitude, so `limit` there
returns an arbitrary three. Real training data separates the weights.

## Tuning

```ruby
Classifier::LogisticRegression.new(
  :positive, :negative,
  learning_rate: 0.1,
  regularization: 0.01,
  max_iterations: 100
)
```

| Parameter | Default | Effect |
|:--|:--|:--|
| `learning_rate` | 0.1 | Step size per iteration. Raise it to train faster, lower it for stability |
| `regularization` | 0.01 | L2 penalty. Raise it to reduce overfit |
| `max_iterations` | 100 | Gradient descent iterations during `fit` |

## Categories

```ruby
classifier.categories
# => ["Positive", "Negative"]

classifier.add_category(:neutral)
```

Call `fit` again after you add a category and train it.

## Save and load

```ruby
classifier.save_to_file("model.json")
loaded = Classifier::LogisticRegression.load_from_file("model.json")
```

A saved model keeps its fitted weights, so a loaded model classifies with no
further `fit`.

See [Persistence](persistence.md) and [Streaming](streaming.md).
