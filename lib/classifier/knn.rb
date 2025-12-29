# rbs_inline: enabled

# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2024 Lucas Carlson
# License::   LGPL

require 'json'
require 'mutex_m'
require 'classifier/lsi'

module Classifier
  # Instance-based classification: stores examples and classifies by similarity.
  #
  # Example:
  #   knn = Classifier::KNN.new(k: 3)
  #   knn.add("spam" => ["Buy now!", "Limited offer!"])
  #   knn.add("ham" => ["Meeting tomorrow", "Project update"])
  #   knn.classify("Special discount!") # => "spam"
  #
  class KNN
    include Mutex_m
    include Streaming

    # @rbs @k: Integer
    # @rbs @weighted: bool
    # @rbs @lsi: LSI
    # @rbs @dirty: bool
    # @rbs @storage: Storage::Base?

    attr_reader :k
    attr_accessor :weighted, :storage

    # Creates a new kNN classifier.
    # @rbs (?k: Integer, ?weighted: bool) -> void
    def initialize(k: 5, weighted: false) # rubocop:disable Naming/MethodParameterName
      super()
      validate_k!(k)
      @k = k
      @weighted = weighted
      @lsi = LSI.new(auto_rebuild: true)
      @dirty = false
      @storage = nil
    end

    # Adds labeled examples. Keys are categories, values are items or arrays.
    # Also aliased as `train` for API consistency with Bayes and LogisticRegression.
    #
    #   knn.add(spam: "Buy now!", ham: "Meeting tomorrow")
    #   knn.train(spam: "Buy now!", ham: "Meeting tomorrow")  # equivalent
    #
    # @rbs (**untyped items) -> void
    def add(**items)
      synchronize { @dirty = true }
      @lsi.add(**items)
    end

    alias train add

    # Classifies text using k nearest neighbors with majority voting.
    # Returns the category as a String for API consistency with Bayes and LogisticRegression.
    # @rbs (String) -> String?
    def classify(text)
      result = classify_with_neighbors(text)
      result[:category]&.to_s
    end

    # Classifies and returns {category:, neighbors:, votes:, confidence:}.
    # @rbs (String) -> Hash[Symbol, untyped]
    def classify_with_neighbors(text)
      synchronize do
        return empty_result if @lsi.items.empty?

        neighbors = find_neighbors(text)
        return empty_result if neighbors.empty?

        votes = tally_votes(neighbors)
        winner = votes.max_by { |_, v| v }&.first
        return empty_result unless winner

        total_votes = votes.values.sum
        confidence = total_votes.positive? ? votes[winner] / total_votes.to_f : 0.0

        { category: winner, neighbors: neighbors, votes: votes, confidence: confidence }
      end
    end

    # @rbs (String) -> Array[String | Symbol]
    def categories_for(item)
      @lsi.categories_for(item)
    end

    # @rbs (String) -> void
    def remove_item(item)
      synchronize { @dirty = true }
      @lsi.remove_item(item)
    end

    # @rbs () -> Array[untyped]
    def items
      @lsi.items
    end

    # Returns all unique categories as strings.
    # @rbs () -> Array[String]
    def categories
      synchronize do
        @lsi.items.flat_map { |item| @lsi.categories_for(item) }.uniq.map(&:to_s)
      end
    end

    # @rbs (Integer) -> void
    def k=(value)
      validate_k!(value)
      @k = value
    end

    # Provides dynamic training methods for categories.
    # For example:
    #   knn.train_spam "Buy now!"
    #   knn.train_ham "Meeting tomorrow"
    def method_missing(name, *args)
      category_match = name.to_s.match(/\Atrain_(\w+)\z/)
      return super unless category_match

      category = category_match[1].to_sym
      args.each { |text| add(category => text) }
    end

    # @rbs (Symbol, ?bool) -> bool
    def respond_to_missing?(name, include_private = false)
      !!(name.to_s =~ /\Atrain_(\w+)\z/) || super
    end

    # @rbs (?untyped) -> untyped
    def as_json(_options = nil)
      {
        version: 1,
        type: 'knn',
        k: @k,
        weighted: @weighted,
        lsi: @lsi.as_json
      }
    end

    # @rbs (?untyped) -> String
    def to_json(_options = nil)
      as_json.to_json
    end

    # Loads a classifier from a JSON string or Hash.
    # @rbs (String | Hash[String, untyped]) -> KNN
    def self.from_json(json)
      data = json.is_a?(String) ? JSON.parse(json) : json
      raise ArgumentError, "Invalid classifier type: #{data['type']}" unless data['type'] == 'knn'

      lsi_data = data['lsi'].dup
      lsi_data['type'] = 'lsi'

      instance = new(k: data['k'], weighted: data['weighted'])
      instance.instance_variable_set(:@lsi, LSI.from_json(lsi_data))
      instance.instance_variable_set(:@dirty, false)
      instance
    end

    # Saves the classifier to the configured storage.
    # @rbs () -> void
    def save
      raise ArgumentError, 'No storage configured. Use save_to_file(path) or set storage=' unless storage

      storage.write(to_json)
      @dirty = false
    end

    # Saves the classifier to a file.
    # @rbs (String) -> Integer
    def save_to_file(path)
      result = File.write(path, to_json)
      @dirty = false
      result
    end

    # Reloads the classifier from configured storage.
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

    # Force reloads, discarding unsaved changes.
    # @rbs () -> self
    def reload!
      raise ArgumentError, 'No storage configured' unless storage

      data = storage.read
      raise StorageError, 'No saved state found' unless data

      restore_from_json(data)
      @dirty = false
      self
    end

    # @rbs () -> bool
    def dirty?
      @dirty
    end

    # Loads a classifier from configured storage.
    # @rbs (storage: Storage::Base) -> KNN
    def self.load(storage:)
      data = storage.read
      raise StorageError, 'No saved state found' unless data

      instance = from_json(data)
      instance.storage = storage
      instance
    end

    # Loads a classifier from a file.
    # @rbs (String) -> KNN
    def self.load_from_file(path)
      from_json(File.read(path))
    end

    # @rbs () -> Array[untyped]
    def marshal_dump
      [@k, @weighted, @lsi, @dirty]
    end

    # @rbs (Array[untyped]) -> void
    def marshal_load(data)
      mu_initialize
      @k, @weighted, @lsi, @dirty = data
      @storage = nil
    end

    # Loads a classifier from a checkpoint.
    #
    # @rbs (storage: Storage::Base, checkpoint_id: String) -> KNN
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
    #
    # @example Train from a file
    #   knn.train_from_stream(:spam, File.open('spam_corpus.txt'))
    #
    # @example With progress tracking
    #   knn.train_from_stream(:spam, io, batch_size: 500) do |progress|
    #     puts "#{progress.completed} documents processed"
    #   end
    #
    # @rbs (String | Symbol, IO, ?batch_size: Integer) { (Streaming::Progress) -> void } -> void
    def train_from_stream(category, io, batch_size: Streaming::DEFAULT_BATCH_SIZE, &block)
      @lsi.train_from_stream(category, io, batch_size: batch_size, &block)
      synchronize { @dirty = true }
    end

    # Adds items in batches.
    #
    # @example Positional style
    #   knn.train_batch(:spam, documents, batch_size: 100)
    #
    # @example Keyword style
    #   knn.train_batch(spam: documents, ham: other_docs)
    #
    # @rbs (?(String | Symbol), ?Array[String], ?batch_size: Integer, **Array[String]) { (Streaming::Progress) -> void } -> void
    def train_batch(category = nil, documents = nil, batch_size: Streaming::DEFAULT_BATCH_SIZE, **categories, &block)
      @lsi.train_batch(category, documents, batch_size: batch_size, **categories, &block)
      synchronize { @dirty = true }
    end

    # Alias add_batch to train_batch for consistency with LSI.
    alias add_batch train_batch

    private

    # @rbs (String) -> Array[Hash[Symbol, untyped]]
    def find_neighbors(text)
      proximity = @lsi.proximity_array_for_content(text)
      neighbors = proximity.reject { |item, _| item == text }.first(@k)

      neighbors.map do |item, similarity|
        {
          item: item,
          category: @lsi.categories_for(item).first,
          similarity: similarity
        }
      end
    end

    # @rbs (Array[Hash[Symbol, untyped]]) -> Hash[String | Symbol, Float]
    def tally_votes(neighbors)
      votes = Hash.new(0.0)

      neighbors.each do |neighbor|
        category = neighbor[:category] or next
        weight = @weighted ? neighbor[:similarity] : 1.0
        votes[category] += weight
      end

      votes
    end

    # @rbs () -> Hash[Symbol, untyped]
    def empty_result
      { category: nil, neighbors: [], votes: {}, confidence: 0.0 }
    end

    # @rbs (Integer) -> void
    def validate_k!(val)
      raise ArgumentError, "k must be a positive integer, got #{val}" unless val.is_a?(Integer) && val.positive?
    end

    # @rbs (String) -> void
    def restore_from_json(json)
      data = JSON.parse(json)
      raise ArgumentError, "Invalid classifier type: #{data['type']}" unless data['type'] == 'knn'

      synchronize do
        @k = data['k']
        @weighted = data['weighted']

        lsi_data = data['lsi'].dup
        lsi_data['type'] = 'lsi'
        @lsi = LSI.from_json(lsi_data)
        @dirty = false
      end
    end
  end
end
