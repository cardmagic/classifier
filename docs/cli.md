# classifier

`classifier` trains and runs text classifiers from the shell. For term scores
rather than categories, use [`keywords`](keywords.md).

## Pre-trained models

The `-r` flag pulls a model from the registry, so classification works with no
training:

```console
$ classifier -r sms-spam-filter "You won a free iPhone"
spam

$ classifier -r imdb-sentiment "This movie was absolutely amazing"
positive

$ classifier models
```

## Train your own

```console
$ classifier train positive reviews/good/*.txt
$ classifier train negative reviews/bad/*.txt

$ classifier "Great product, highly recommend"
positive
```

Training reads standard input when you name no file:

```console
$ echo "amazing fantastic" | classifier train positive
```

The default model file is `./classifier.json`. Use `-f` for any other path. Each
`train` call updates that file in place.

## Probabilities

```console
$ classifier -p "Great product, highly recommend"
positive:0.89 negative:0.11
```

## Model information

```console
$ classifier info
{
  "file": "./classifier.json",
  "type": "bayes",
  "categories": [
    "Positive",
    "Negative"
  ],
  "category_stats": {
    "Positive": {
      "unique_words": 7,
      "total_words": 7
    },
    "Negative": {
      "unique_words": 7,
      "total_words": 7
    }
  }
}
```

## Other classifiers

`-m` selects the algorithm. The default is `bayes`.

```console
$ classifier -m knn -k 3 train tech docs/tech/*.txt
$ classifier -m lr train positive reviews/good/*.txt
$ classifier -m lsi train dogs corpus/dogs/*.txt
```

Logistic regression needs a fit step after training:

```console
$ classifier -m lr train positive reviews/good/*.txt
$ classifier -m lr train negative reviews/bad/*.txt
$ classifier -m lr fit
Model fitted successfully
$ classifier -m lr "I love it"
positive
```

## Search and related documents

These two commands need an LSI model.

```console
$ classifier -m lsi search "machine learning"
$ classifier -m lsi related article.txt
```

`-n` sets how many results come back. The default is 10.

## Commands

| Command | Action |
|:--|:--|
| `train <category> [files...]` | Train a category from files or standard input |
| `info` | Print model information |
| `fit` | Fit the model. Logistic regression only |
| `search <query>` | Semantic search. LSI only |
| `related <item>` | Find related documents. LSI only |
| `models [registry]` | List the models in a registry |
| `pull <model>` | Download a model from the registry |
| `push <file>` | Contribute a model to the registry |
| `<text>` | Classify the text. The default action |

## Options

| Option | Meaning |
|:--|:--|
| `-f`, `--file FILE` | Model file. Default `./classifier.json` |
| `-m`, `--model TYPE` | Algorithm: `bayes`, `lsi`, `knn`, or `lr`. Default `bayes` |
| `-r`, `--remote MODEL` | Use a remote model, by name or `@user/repo:name` |
| `--search TEXT` | Search remote models by name and description, and local models by name |
| `-o`, `--output FILE` | Output path for `pull` |
| `-p` | Print probabilities |
| `-n`, `--count N` | Result count for `search` and `related`. Default 10 |
| `-k`, `--neighbors N` | Neighbor count for kNN. Default 5 |
| `--weighted` | Use distance-weighted voting for kNN |
| `--learning-rate N` | Learning rate for logistic regression. Default 0.1 |
| `--regularization N` | L2 regularization for logistic regression. Default 0.01 |
| `--max-iterations N` | Maximum iterations for logistic regression. Default 100 |
| `-q` | Quiet mode |
| `--local` | List locally cached models, with the `models` command |
| `-v`, `--version` | Print the gem version |
| `-h`, `--help` | Print the full usage |

## Using both commands together

`classifier` and `keywords` answer different questions about the same text.
`classifier` gives a category. `keywords` gives the terms that carry the text.
Run them side by side to see the label and the reason behind it.

Fit a vocabulary from the same corpus you train on, and the two views line up:

```console
$ keywords fit -m reviews.json reviews/good/*.txt reviews/bad/*.txt
$ keywords info -m reviews.json
Documents: 8
Vocabulary: 37
Min DF: 1
Max DF: 1.0
```

`keywords info` reports the corpus before you commit to training. A vocabulary
of 37 terms over 8 documents says the corpus is far too small, and no
classifier fixes that.

Then train, and read the two answers together:

```console
$ classifier -f reviews-model.json train positive reviews/good/*.txt
$ classifier -f reviews-model.json train negative reviews/bad/*.txt

$ classifier -f reviews-model.json -p "Broken on arrival, awful quality and useless customer service"
positive:0.07 negative:0.93

$ keywords -m reviews.json -n 5 "Broken on arrival, awful quality and useless customer service"
useless:0.4 awful:0.4 arrival:0.4 broken:0.4 service:0.34
```

The first line is the verdict. The second says which terms drove it, which is
what you need when a classification surprises you.

### Find the words your corpus wastes on itself

A term that appears in nearly every document tells a classifier nothing, and
every corpus grows its own. A review corpus repeats `delivery`, a support
corpus repeats `ticket`. These are stopwords that no general stopword list
knows about, because they are specific to your data.

`keywords` finds them, because `--max-df` drops a term that appears in more
than the given ratio of documents. Compare the vocabulary size before and
after:

```console
$ keywords fit -m default.json good.txt bad.txt
$ keywords info -m default.json
Documents: 12
Vocabulary: 42

$ keywords fit -m pruned.json --max-df 0.5 good.txt bad.txt
$ keywords info -m pruned.json
Documents: 12
Vocabulary: 41
```

One term went. Score a document under each model to see which:

```console
$ keywords -m default.json -n 3 "delivery was awful and broken"
broken:0.69 awful:0.69 delivery:0.24

$ keywords -m pruned.json -n 3 "delivery was awful and broken"
broken:0.71 awful:0.71
```

`delivery` sat in all 12 documents and still drew weight. Dropping it sharpens
every term that carries real signal.

Watch the vocabulary count as you tune, because these bounds cut fast:

```console
$ keywords fit -m tight.json --min-df 2 good.txt bad.txt
$ keywords info -m tight.json
Documents: 12
Vocabulary: 7
```

`--min-df 2` took 42 terms down to 7. That is no longer a vocabulary, it is a
handful of words. Move one bound at a time and read `keywords info` after each
change.

### Two commands, two models

The models are separate files in separate formats, and neither command reads
the other's:

```console
$ classifier -f reviews.json "broken awful"
Error: Unknown classifier type in model: tfidf

$ keywords -m reviews-model.json "broken awful"
Error: Invalid vectorizer type: bayes
```

Note the flags differ too. `classifier` takes `-f`, and `keywords` takes `-m`.

| | `classifier` | `keywords` |
|:--|:--|:--|
| Answers | Which category | Which terms matter |
| Model flag | `-f` | `-m` |
| Default model | `./classifier.json` | `./keywords.json` |
| Builds a model with | `train` | `fit` |
| Pre-trained models | Yes, through `-r` | No |

### Do not pipe one into the other

`keywords` prints `term:score` pairs, which is not text to classify. Feeding
its output to `classifier` throws away the rest of the document and weakens the
result:

```console
$ classifier -f reviews-model.json -p "$LONG_REVIEW"
positive:0.08 negative:0.92        # the whole review

$ keywords -m reviews.json -n 4 "$LONG_REVIEW"
arrived:0.6 refund:0.3 useless:0.3 build:0.3

$ classifier -f reviews-model.json -p "arrived refund useless build"
positive:0.21 negative:0.79        # weaker, from the top terms alone
```

Confidence drops from 0.92 to 0.79. TF-IDF ranks a term by how much it
distinguishes one document from the rest of the corpus, which is not the same
as how much it signals a category. Here it puts `arrived` first, a neutral
word about delivery. Classify the full text and use `keywords` to explain it.

## Install without Ruby

Homebrew installs the command line tools on their own:

```bash
brew install classifier
```
