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

## Install without Ruby

Homebrew installs the command line tools on their own:

```bash
brew install cardmagic/tap/classifier
```
