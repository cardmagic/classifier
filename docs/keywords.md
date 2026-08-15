# keywords

`keywords` scores the terms of a text with TF-IDF. It prints `term:score` pairs
in descending order of score.

The gem installs this command next to `classifier`.

## A model comes first

`keywords` ships no pre-trained models. Build a vocabulary before you score any
text:

```console
$ keywords fit corpus/*.txt
Saved to "/path/to/keywords.json"
```

A command that needs a model and finds none exits 2:

```console
$ keywords "Ruby is elegant"
Error: No model found; run 'keywords fit' first or pass correct model using the '-m' option.
```

The default model path is `./keywords.json`. Use `-m` for any other path.

## Commands

| Command | Action |
|:--|:--|
| `keywords fit <files...>` | Build a vocabulary from files or standard input |
| `keywords extract <file>` | Score the contents of one file |
| `keywords info` | Print the model statistics |
| `keywords <text>` | Score the text given as arguments |

With no arguments and no piped input, `keywords` prints a short guide.

## fit

Each **line** becomes a separate document. The document count drives the inverse
document frequency, so a file of 200 lines contributes 200 documents.

```console
$ keywords fit corpus/*.txt
Saved to "/path/to/keywords.json"

$ cat documents.txt | keywords fit
Saved to "/path/to/keywords.json"

$ keywords fit --min-df 2 --max-df 0.85 --ngram 1,2 corpus/*.txt
Saved to "/path/to/keywords.json"
```

`fit` skips a directory and keeps the files beside it, so a shell glob works
even when the directory holds a subdirectory:

```console
$ ls corpus
a.txt   b.txt   archive/
$ keywords fit corpus/*
Saved to "/path/to/keywords.json"
```

A path that matches nothing stops the run, so a typo never produces a smaller
model in silence:

```console
$ keywords fit corpus/a.txt corpus/NOPE.txt
Error: No files matched "corpus/NOPE.txt"
```

An argument set with no readable file at all reports `No files to fit`. Empty
input reports `No documents found to save the model`. Neither writes a model.

`fit` reads one file at a time, so a corpus larger than the file descriptor
limit still works.

## extract

```console
$ keywords extract article.txt
machine:0.58 network:0.47 neural:0.47 learning:0.47

$ curl -s https://example.com/article | keywords extract
```

`extract` requires a real file. A path that does not exist, or a directory,
exits 2. To score literal text, use the bare form instead.

## info

```console
$ keywords info
Documents: 1,234
Vocabulary: 5,678
Min DF: 1
Max DF: 1.0
```

## Options

| Option | Meaning |
|:--|:--|
| `-m`, `--model FILE` | Model file. Default `./keywords.json` |
| `-n`, `--top N` | Print the top N terms only. N must be positive |
| `-q` | Quiet. Suppress the `Saved to` line from `fit` |
| `--min-df N` | Minimum document frequency, as a count. Default 1 |
| `--max-df N` | Maximum document frequency, as a ratio from 0.0 to 1.0. Default 1.0 |
| `--ngram MIN,MAX` | N-gram range. Default `1,1` |
| `-v`, `--version` | Print the gem version |
| `-h`, `--help` | Print the full usage |

`--min-df` and `--max-df` apply during `fit`. The model stores them, and `info`
reports them back.

`-q` suppresses progress text but never the term scores. A scripted `fit` stays
silent, and a scripted score still produces its data.

## Output format

Terms print as `term:score`, separated by spaces, sorted by descending score.

The command maps stems back to whole words. A model built from `programming`
prints `programming`, not the `program` stem:

```console
$ keywords "Ruby is a programming language"
language:0.58 programming:0.58 ruby:0.58
```

An n-gram label joins its parts with a space:

```console
$ keywords fit --ngram 1,2 -m ng.json corpus/*.txt
$ keywords -m ng.json "machine learning neural networks"
machine learning:0.46 machine:0.46 neural networks:0.38 networks:0.38 neural:0.38 learning:0.38
```

Each score depends on the corpus you fitted, so your numbers will differ.

That space sits inside a label in an otherwise space-separated stream. Parse
n-gram output on the `:` separator, not on whitespace.

## Exit codes

| Code | Meaning |
|:--|:--|
| 0 | Success |
| 1 | An unexpected error |
| 2 | A usage error, such as a bad option, a missing model, or a path that matches nothing |

Scripts can rely on 2 for every input mistake:

```bash
keywords fit corpus/*.txt || echo "fit failed with $?"
```

## Equivalent Ruby

The command wraps [`Classifier::TFIDF`](tfidf.md). This code does what
`keywords fit` does:

```ruby
require "classifier"

tfidf = Classifier::TFIDF.new(min_df: 2, max_df: 0.85, ngram_range: [1, 2])
tfidf.fit_from_stream(
  Classifier::Streaming::MultiIO.new(Dir["corpus/*.txt"])
)
tfidf.save_to_file("keywords.json")
```
