# /classifier:classify

Classify text using a pre-trained or custom model.

## Usage

```
/classifier:classify <model> <text>
```

## Examples

```
/classifier:classify sms-spam-filter "Congratulations! You won $1000"
/classifier:classify imdb-sentiment "This movie was fantastic"
/classifier:classify emotion-detection "I feel so frustrated today"
```

## Instructions

Run the classifier command with the specified model and text:

```bash
classifier -r "$model" "$text"
```

If no model is specified, list available models with `classifier models` and ask the user which one to use.

Report the classification result clearly, e.g.:
- "The text was classified as: **spam**"
- "Sentiment: **positive**"
- "Detected emotion: **anger**"
