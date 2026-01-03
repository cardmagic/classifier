# Text Classification with Classifier

Use when: User asks to classify text, detect spam, analyze sentiment, detect emotions, or use pre-trained ML models.

## Pre-trained Models

Run `classifier models` to see all available models. Common ones:

| Model | Command | Use Case |
|-------|---------|----------|
| `sms-spam-filter` | `classifier -r sms-spam-filter "text"` | Spam detection |
| `imdb-sentiment` | `classifier -r imdb-sentiment "text"` | Sentiment analysis |
| `emotion-detection` | `classifier -r emotion-detection "text"` | Emotion classification |

## Quick Classification

```bash
# Classify with a pre-trained model
classifier -r <model-name> "text to classify"

# Example: detect spam
classifier -r sms-spam-filter "You won a free iPhone! Click here now!"

# Example: sentiment analysis
classifier -r imdb-sentiment "This movie was absolutely terrible"

# Example: emotion detection
classifier -r emotion-detection "I am so happy today"
```

## Custom Training

```bash
# Train from text
classifier train positive "Great product, love it"
classifier train negative "Terrible quality, waste of money"

# Train from files
classifier train positive reviews/good/*.txt
classifier train negative reviews/bad/*.txt

# Classify after training
classifier "This product exceeded my expectations"
```

## Model Management

```bash
# List all available models
classifier models

# Show model details
classifier info <model-name>

# Save trained model
classifier save my-model.json

# Load saved model
classifier load my-model.json
```

## Best Practices

1. For quick classification tasks, use pre-trained models first
2. For custom domains, train with representative examples from each category
3. Use `classifier models` to discover available pre-trained models
4. Balance training data across categories for best results
