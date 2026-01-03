# /classifier:train

Train a classifier with labeled examples.

## Usage

```
/classifier:train <category> <text or file pattern>
```

## Examples

```
/classifier:train spam "Buy cheap viagra now"
/classifier:train ham "Meeting scheduled for tomorrow"
/classifier:train positive reviews/good/*.txt
/classifier:train negative reviews/bad/*.txt
```

## Instructions

Run the classifier train command:

```bash
classifier train "$category" "$text_or_pattern"
```

After training, inform the user they can:
1. Add more training examples with additional `/classifier:train` commands
2. Classify new text with `classifier "text to classify"`
3. Save the model with `classifier save model-name.json`

For best results, recommend balanced training data across all categories.
