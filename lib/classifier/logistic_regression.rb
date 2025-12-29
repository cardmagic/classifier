# rbs_inline: enabled

# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2024 Lucas Carlson
# License::   LGPL

require 'json'
require 'mutex_m'

module Classifier
  # Logistic Regression (MaxEnt) classifier using Stochastic Gradient Descent.
  # Often provides better accuracy than Naive Bayes while remaining fast and interpretable.
  #
  # Example:
  #   classifier = Classifier::LogisticRegression.new(:spam, :ham)
  #   classifier.train(spam: ["Buy now!", "Free money!!!"])
  #   classifier.train(ham: ["Meeting tomorrow", "Project update"])
  #   classifier.classify("Claim your prize!") # => "Spam"
  #   classifier.probabilities("Claim your prize!") # => {"Spam" => 0.92, "Ham" => 0.08}
  #
  class LogisticRegression # rubocop:disable Metrics/ClassLength
    include Mutex_m
    include Streaming

    # @rbs @categories: Array[Symbol]
    # @rbs @weights: Hash[Symbol, Hash[Symbol, Float]]
    # @rbs @bias: Hash[Symbol, Float]
    # @rbs @vocabulary: Hash[Symbol, bool]
    # @rbs @training_data: Array[{category: Symbol, features: Hash[Symbol, Integer]}]
    # @rbs @learning_rate: Float
    # @rbs @regularization: Float
    # @rbs @max_iterations: Integer
    # @rbs @tolerance: Float
    # @rbs @fitted: bool
    # @rbs @dirty: bool
    # @rbs @storage: Storage::Base?

    attr_accessor :storage

    DEFAULT_LEARNING_RATE = 0.1
    DEFAULT_REGULARIZATION = 0.01
    DEFAULT_MAX_ITERATIONS = 100
    DEFAULT_TOLERANCE = 1e-4

    # Creates a new Logistic Regression classifier with the specified categories.
    #
    #   classifier = Classifier::LogisticRegression.new(:spam, :ham)
    #   classifier = Classifier::LogisticRegression.new('Positive', 'Negative', 'Neutral')
    #
    # Options:
    # - learning_rate: Step size for gradient descent (default: 0.1)
    # - regularization: L2 regularization strength (default: 0.01)
    # - max_iterations: Maximum training iterations (default: 100)
    # - tolerance: Convergence threshold (default: 1e-4)
    #
    # @rbs (*String | Symbol, ?learning_rate: Float, ?regularization: Float,
    #       ?max_iterations: Integer, ?tolerance: Float) -> void
    def initialize(*categories, learning_rate: DEFAULT_LEARNING_RATE,
                   regularization: DEFAULT_REGULARIZATION,
                   max_iterations: DEFAULT_MAX_ITERATIONS,
                   tolerance: DEFAULT_TOLERANCE)
      super()
      raise ArgumentError, 'At least two categories required' if categories.size < 2

      @categories = categories.map { |c| c.to_s.prepare_category_name }
      @weights = @categories.to_h { |c| [c, {}] }
      @bias = @categories.to_h { |c| [c, 0.0] }
      @vocabulary = {}
      @training_data = []
      @learning_rate = learning_rate
      @regularization = regularization
      @max_iterations = max_iterations
      @tolerance = tolerance
      @fitted = false
      @dirty = false
      @storage = nil
    end

    # Trains the classifier with text for a category.
    #
    #   classifier.train(spam: "Buy now!", ham: ["Hello", "Meeting tomorrow"])
    #   classifier.train(:spam, "legacy positional API")
    #
    # @rbs (?(String | Symbol)?, ?String?, **(String | Array[String])) -> void
    def train(category = nil, text = nil, **categories)
      return train_single(category, text) if category && text

      categories.each do |cat, texts|
        (texts.is_a?(Array) ? texts : [texts]).each { |t| train_single(cat, t) }
      end
    end

    # Fits the model to all accumulated training data.
    # Called automatically during classify/probabilities if not already fitted.
    #
    # @rbs () -> self
    def fit
      synchronize do
        return self if @training_data.empty?

        optimize_weights
        @fitted = true
        @dirty = false
      end
      self
    end

    # Returns the best matching category for the provided text.
    #
    #   classifier.classify("Buy now!") # => "Spam"
    #
    # @rbs (String) -> String
    def classify(text)
      probs = probabilities(text)
      best = probs.max_by { |_, v| v }
      raise StandardError, 'No classifications available' unless best

      best.first
    end

    # Returns probability distribution across all categories.
    # Probabilities are well-calibrated (unlike Naive Bayes).
    #
    #   classifier.probabilities("Buy now!")
    #   # => {"Spam" => 0.92, "Ham" => 0.08}
    #
    # @rbs (String) -> Hash[String, Float]
    def probabilities(text)
      fit unless @fitted

      features = text.word_hash
      synchronize do
        softmax(compute_scores(features))
      end
    end

    # Returns log-odds scores for each category (before softmax).
    #
    # @rbs (String) -> Hash[String, Float]
    def classifications(text)
      fit unless @fitted

      features = text.word_hash
      synchronize do
        compute_scores(features).transform_keys(&:to_s)
      end
    end

    # Returns feature weights for a category, sorted by importance.
    # Positive weights indicate the feature supports the category.
    #
    #   classifier.weights(:spam)
    #   # => {:free => 2.3, :buy => 1.8, :money => 1.5, ...}
    #
    # @rbs (String | Symbol, ?limit: Integer?) -> Hash[Symbol, Float]
    def weights(category, limit: nil)
      fit unless @fitted

      cat = category.to_s.prepare_category_name
      raise StandardError, "No such category: #{cat}" unless @weights.key?(cat)

      sorted = @weights[cat].sort_by { |_, v| -v.abs }
      sorted = sorted.first(limit) if limit
      sorted.to_h
    end

    # Returns the list of categories.
    #
    # @rbs () -> Array[String]
    def categories
      synchronize { @categories.map(&:to_s) }
    end

    # Returns true if the model has been fitted.
    #
    # @rbs () -> bool
    def fitted?
      @fitted
    end

    # Returns true if there are unsaved changes.
    #
    # @rbs () -> bool
    def dirty?
      @dirty
    end

    # Provides training methods for the categories.
    #   classifier.train_spam "Buy now!"
    def method_missing(name, *args)
      category_match = name.to_s.match(/train_(\w+)/)
      return super unless category_match

      category = category_match[1].to_s.prepare_category_name
      raise StandardError, "No such category: #{category}" unless @categories.include?(category)

      args.each { |text| train(category, text) }
    end

    # @rbs (Symbol, ?bool) -> bool
    def respond_to_missing?(name, include_private = false)
      !!(name.to_s =~ /train_(\w+)/) || super
    end

    # Returns a hash representation of the classifier state.
    #
    # @rbs (?untyped) -> Hash[Symbol, untyped]
    def as_json(_options = nil)
      fit unless @fitted

      {
        version: 1,
        type: 'logistic_regression',
        categories: @categories.map(&:to_s),
        weights: @weights.transform_keys(&:to_s).transform_values { |v| v.transform_keys(&:to_s) },
        bias: @bias.transform_keys(&:to_s),
        vocabulary: @vocabulary.keys.map(&:to_s),
        learning_rate: @learning_rate,
        regularization: @regularization,
        max_iterations: @max_iterations,
        tolerance: @tolerance
      }
    end

    # Serializes the classifier state to a JSON string.
    #
    # @rbs (?untyped) -> String
    def to_json(_options = nil)
      JSON.generate(as_json)
    end

    # Loads a classifier from a JSON string or Hash.
    #
    # @rbs (String | Hash[String, untyped]) -> LogisticRegression
    def self.from_json(json)
      data = json.is_a?(String) ? JSON.parse(json) : json
      raise ArgumentError, "Invalid classifier type: #{data['type']}" unless data['type'] == 'logistic_regression'

      categories = data['categories'].map(&:to_sym)
      instance = allocate
      instance.send(:restore_state, data, categories)
      instance
    end

    # Saves the classifier to the configured storage.
    #
    # @rbs () -> void
    def save
      raise ArgumentError, 'No storage configured' unless storage

      storage.write(to_json)
      @dirty = false
    end

    # Saves the classifier state to a file.
    #
    # @rbs (String) -> Integer
    def save_to_file(path)
      result = File.write(path, to_json)
      @dirty = false
      result
    end

    # Loads a classifier from the configured storage.
    #
    # @rbs (storage: Storage::Base) -> LogisticRegression
    def self.load(storage:)
      data = storage.read
      raise StorageError, 'No saved state found' unless data

      instance = from_json(data)
      instance.storage = storage
      instance
    end

    # Loads a classifier from a file.
    #
    # @rbs (String) -> LogisticRegression
    def self.load_from_file(path)
      from_json(File.read(path))
    end

    # Reloads the classifier from storage, raising if there are unsaved changes.
    #
    # @rbs () -> self
    def reload
      raise ArgumentError, 'No storage configured' unless storage
      raise UnsavedChangesError, 'Unsaved changes would be lost. Call save first or use reload!' if @dirty

      data = storage.read
      raise StorageError, 'No saved state found' unless data

      restore_from_json(data)
      @dirty = false
      self
    end

    # Force reloads the classifier from storage, discarding any unsaved changes.
    #
    # @rbs () -> self
    def reload!
      raise ArgumentError, 'No storage configured' unless storage

      data = storage.read
      raise StorageError, 'No saved state found' unless data

      restore_from_json(data)
      @dirty = false
      self
    end

    # Custom marshal serialization to exclude mutex state.
    #
    # @rbs () -> Array[untyped]
    def marshal_dump
      fit unless @fitted
      [@categories, @weights, @bias, @vocabulary, @learning_rate, @regularization,
       @max_iterations, @tolerance, @fitted]
    end

    # Custom marshal deserialization to recreate mutex.
    #
    # @rbs (Array[untyped]) -> void
    def marshal_load(data)
      mu_initialize
      @categories, @weights, @bias, @vocabulary, @learning_rate, @regularization,
        @max_iterations, @tolerance, @fitted = data
      @training_data = []
      @dirty = false
      @storage = nil
    end

    # Loads a classifier from a checkpoint.
    #
    # @rbs (storage: Storage::Base, checkpoint_id: String) -> LogisticRegression
    def self.load_checkpoint(storage:, checkpoint_id:)
      raise ArgumentError, 'Storage must be File storage for checkpoints' unless storage.is_a?(Storage::File)

      dir = File.dirname(storage.path)
      base = File.basename(storage.path, '.*')
      ext = File.extname(storage.path)
      checkpoint_path = File.join(dir, "#{base}_checkpoint_#{checkpoint_id}#{ext}")

      checkpoint_storage = Storage::File.new(path: checkpoint_path)
      instance = load(storage: checkpoint_storage)
      instance.storage = storage
      instance
    end

    # Trains the classifier from an IO stream.
    # Each line in the stream is treated as a separate document.
    # Note: The model is NOT automatically fitted after streaming.
    # Call #fit to train the model after adding all data.
    #
    # @example Train from a file
    #   classifier.train_from_stream(:spam, File.open('spam_corpus.txt'))
    #   classifier.fit  # Required to train the model
    #
    # @example With progress tracking
    #   classifier.train_from_stream(:spam, io, batch_size: 500) do |progress|
    #     puts "#{progress.completed} documents processed"
    #   end
    #   classifier.fit
    #
    # @rbs (String | Symbol, IO, ?batch_size: Integer) { (Streaming::Progress) -> void } -> void
    def train_from_stream(category, io, batch_size: Streaming::DEFAULT_BATCH_SIZE)
      category = category.to_s.prepare_category_name
      raise StandardError, "No such category: #{category}" unless @categories.include?(category)

      reader = Streaming::LineReader.new(io, batch_size: batch_size)
      total = reader.estimate_line_count
      progress = Streaming::Progress.new(total: total)

      reader.each_batch do |batch|
        synchronize do
          batch.each do |text|
            features = text.word_hash
            features.each_key { |word| @vocabulary[word] = true }
            @training_data << { category: category, features: features }
          end
          @fitted = false
          @dirty = true
        end
        progress.completed += batch.size
        progress.current_batch += 1
        yield progress if block_given?
      end
    end

    # Trains the classifier with an array of documents in batches.
    # Note: The model is NOT automatically fitted after batch training.
    # Call #fit to train the model after adding all data.
    #
    # @example Positional style
    #   classifier.train_batch(:spam, documents, batch_size: 100)
    #   classifier.fit
    #
    # @example Keyword style
    #   classifier.train_batch(spam: documents, ham: other_docs)
    #   classifier.fit
    #
    # @rbs (?(String | Symbol)?, ?Array[String]?, ?batch_size: Integer, **Array[String]) { (Streaming::Progress) -> void } -> void
    def train_batch(category = nil, documents = nil, batch_size: Streaming::DEFAULT_BATCH_SIZE, **categories, &block)
      if category && documents
        train_batch_for_category(category, documents, batch_size: batch_size, &block)
      else
        categories.each do |cat, docs|
          train_batch_for_category(cat, Array(docs), batch_size: batch_size, &block)
        end
      end
    end

    private

    # Trains a batch of documents for a single category.
    # @rbs (String | Symbol, Array[String], ?batch_size: Integer) { (Streaming::Progress) -> void } -> void
    def train_batch_for_category(category, documents, batch_size: Streaming::DEFAULT_BATCH_SIZE)
      category = category.to_s.prepare_category_name
      raise StandardError, "No such category: #{category}" unless @categories.include?(category)

      progress = Streaming::Progress.new(total: documents.size)

      documents.each_slice(batch_size) do |batch|
        synchronize do
          batch.each do |text|
            features = text.word_hash
            features.each_key { |word| @vocabulary[word] = true }
            @training_data << { category: category, features: features }
          end
          @fitted = false
          @dirty = true
        end
        progress.completed += batch.size
        progress.current_batch += 1
        yield progress if block_given?
      end
    end

    # Core training logic for a single category and text.
    # @rbs (String | Symbol, String) -> void
    def train_single(category, text)
      category = category.to_s.prepare_category_name
      raise StandardError, "No such category: #{category}" unless @categories.include?(category)

      features = text.word_hash
      synchronize do
        features.each_key { |word| @vocabulary[word] = true }
        @training_data << { category: category, features: features }
        @fitted = false
        @dirty = true
      end
    end

    # Optimizes weights using mini-batch SGD with L2 regularization.
    # @rbs () -> void
    def optimize_weights
      return if @training_data.empty?

      initialize_weights
      prev_loss = Float::INFINITY

      @max_iterations.times do
        total_loss = run_training_epoch
        break if (prev_loss - total_loss).abs < @tolerance

        prev_loss = total_loss
      end

      @training_data = []
    end

    # @rbs () -> void
    def initialize_weights
      @vocabulary.each_key do |word|
        @categories.each { |cat| @weights[cat][word] ||= 0.0 }
      end
    end

    # @rbs () -> Float
    def run_training_epoch
      total_loss = 0.0

      @training_data.shuffle.each do |sample|
        probs = softmax(compute_scores(sample[:features]))
        update_weights(sample[:features], sample[:category], probs)
        total_loss -= Math.log([probs[sample[:category].to_s], 1e-15].max)
      end

      total_loss + l2_penalty
    end

    # @rbs (Hash[Symbol, Integer], Symbol, Hash[String, Float]) -> void
    def update_weights(features, true_category, probs)
      @categories.each do |cat|
        error = probs[cat.to_s] - (cat == true_category ? 1.0 : 0.0)
        @bias[cat] -= @learning_rate * error

        features.each do |word, count|
          gradient = (error * count) + (@regularization * (@weights[cat][word] || 0.0))
          @weights[cat][word] ||= 0.0
          @weights[cat][word] -= @learning_rate * gradient
        end
      end
    end

    # @rbs () -> Float
    def l2_penalty
      penalty = 0.0
      @weights.each_value do |cat_weights|
        cat_weights.each_value { |w| penalty += 0.5 * @regularization * w * w }
      end
      penalty
    end

    # Computes raw scores (logits) for each category.
    # @rbs (Hash[Symbol, Integer]) -> Hash[Symbol, Float]
    def compute_scores(features)
      @categories.to_h do |cat|
        score = @bias[cat]
        features.each { |word, count| score += (@weights[cat][word] || 0.0) * count }
        [cat, score]
      end
    end

    # Applies softmax to convert scores to probabilities.
    # @rbs (Hash[Symbol, Float]) -> Hash[String, Float]
    def softmax(scores)
      max_score = scores.values.max || 0.0
      exp_scores = scores.transform_values { |s| Math.exp(s - max_score) }
      sum = exp_scores.values.sum.to_f
      exp_scores.transform_keys(&:to_s).transform_values { |e| (e / sum).to_f }
    end

    # Restores classifier state from JSON string.
    # @rbs (String) -> void
    def restore_from_json(json)
      data = JSON.parse(json)
      categories = data['categories'].map(&:to_sym)
      restore_state(data, categories)
    end

    # Restores classifier state from parsed JSON data.
    # @rbs (Hash[String, untyped], Array[Symbol]) -> void
    def restore_state(data, categories)
      mu_initialize
      @categories = categories
      @weights = {}
      @bias = {}

      data['weights'].each do |cat, words|
        @weights[cat.to_sym] = words.transform_keys(&:to_sym).transform_values(&:to_f)
      end

      data['bias'].each do |cat, value|
        @bias[cat.to_sym] = value.to_f
      end

      @vocabulary = data['vocabulary'].to_h { |v| [v.to_sym, true] }
      @learning_rate = data['learning_rate']
      @regularization = data['regularization']
      @max_iterations = data['max_iterations']
      @tolerance = data['tolerance']
      @training_data = []
      @fitted = true
      @dirty = false
      @storage = nil
    end
  end
end
