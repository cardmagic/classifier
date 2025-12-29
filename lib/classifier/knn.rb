# rbs_inline: enabled

# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2024 Lucas Carlson
# License::   LGPL

require 'json'
require 'mutex_m'
require 'classifier/lsi'

module Classifier
  # This class implements a k-Nearest Neighbors classifier that leverages
  # the existing LSI infrastructure for similarity computations.
  #
  # Unlike traditional classifiers that require training, kNN uses instance-based
  # learning - it stores examples and classifies by finding the most similar ones.
  #
  # Example usage:
  #   knn = Classifier::KNN.new(k: 3)
  #   knn.add("spam" => ["Buy now!", "Limited offer!"])
  #   knn.add("ham" => ["Meeting tomorrow", "Project update"])
  #   knn.classify("Special discount!") # => "spam"
  #
  class KNN
    include Mutex_m

    # @rbs @k: Integer
    # @rbs @weighted: bool
    # @rbs @lsi: LSI
    # @rbs @dirty: bool
    # @rbs @storage: Storage::Base?

    attr_reader :k
    attr_accessor :weighted, :storage

    # Creates a new kNN classifier.
    #
    # @param k [Integer] Number of neighbors to consider (default: 5)
    # @param weighted [Boolean] Use distance-weighted voting (default: false)
    #
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

    # Adds labeled examples to the classifier using hash-style syntax.
    # Keys are categories, values are items (or arrays of items).
    #
    # @example Single item per category
    #   knn.add("spam" => "Buy now!")
    #   knn.add("ham" => "Meeting tomorrow")
    #
    # @example Multiple items per category
    #   knn.add("spam" => ["Buy now!", "Limited offer!"])
    #
    # @example Batch operations
    #   knn.add(
    #     "spam" => ["Buy now!", "Limited offer!"],
    #     "ham" => ["Meeting tomorrow", "Project update"]
    #   )
    #
    # @rbs (**untyped items) -> void
    def add(**items)
      synchronize { @dirty = true }
      @lsi.add(**items)
    end

    # Adds a single labeled example to the classifier.
    #
    # @deprecated Use {#add} instead for clearer hash-style syntax.
    #
    # @param item [String] The text content to add
    # @param category [String, Symbol] The category/label for this item
    #
    # @rbs (String, String | Symbol) -> void
    def add_item(item, category)
      synchronize { @dirty = true }
      @lsi.add_item(item, category)
    end

    # Classifies the given text by finding the k nearest neighbors
    # and using majority voting.
    #
    # @param text [String] The text to classify
    # @return [String, Symbol, nil] The predicted category, or nil if no examples exist
    #
    # @rbs (String) -> (String | Symbol)?
    def classify(text)
      result = classify_with_neighbors(text)
      result[:category]
    end

    # Classifies the given text and returns detailed information about
    # the neighbors that contributed to the decision.
    #
    # @param text [String] The text to classify
    # @return [Hash] A hash containing:
    #   - :category - The predicted category
    #   - :neighbors - Array of neighbor details (item, category, similarity)
    #   - :votes - Hash of category => vote count/weight
    #   - :confidence - Confidence score (winning vote share)
    #
    # @rbs (String) -> Hash[Symbol, untyped]
    def classify_with_neighbors(text)
      synchronize do
        return empty_result if @lsi.items.empty?

        neighbors = find_neighbors(text)
        return empty_result if neighbors.empty?

        votes = tally_votes(neighbors)
        winner = votes.max_by { |_, v| v }&.first
        total_votes = votes.values.sum
        confidence = winner && total_votes.positive? ? votes[winner] / total_votes.to_f : 0.0

        {
          category: winner,
          neighbors: neighbors,
          votes: votes,
          confidence: confidence
        }
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

    # @rbs () -> Array[String | Symbol]
    def categories
      synchronize do
        @lsi.items.flat_map { |item| @lsi.categories_for(item) }.uniq
      end
    end

    # @rbs (Integer) -> void
    def k=(value)
      validate_k!(value)
      @k = value
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
    #
    # @param json [String, Hash] JSON string or parsed hash
    # @return [KNN] A new KNN instance with restored state
    #
    # @rbs (String | Hash[String, untyped]) -> KNN
    def self.from_json(json)
      data = json.is_a?(String) ? JSON.parse(json) : json
      raise ArgumentError, "Invalid classifier type: #{data['type']}" unless data['type'] == 'knn'

      # Restore the LSI from its nested data
      lsi_data = data['lsi']
      lsi_data['type'] = 'lsi' # Ensure type is set for LSI.from_json

      instance = new(k: data['k'], weighted: data['weighted'])
      instance.instance_variable_set(:@lsi, LSI.from_json(lsi_data))
      instance.instance_variable_set(:@dirty, false)
      instance
    end

    # Saves the classifier to the configured storage.
    #
    # @rbs () -> void
    def save
      raise ArgumentError, 'No storage configured. Use save_to_file(path) or set storage=' unless storage

      storage.write(to_json)
      @dirty = false
    end

    # Saves the classifier to a file.
    #
    # @param path [String] The file path
    # @return [Integer] Number of bytes written
    #
    # @rbs (String) -> Integer
    def save_to_file(path)
      result = File.write(path, to_json)
      @dirty = false
      result
    end

    # Reloads the classifier from configured storage.
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

    # Force reloads the classifier from storage.
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

    # @rbs () -> bool
    def dirty?
      @dirty
    end

    # Loads a classifier from configured storage.
    #
    # @param storage [Storage::Base] The storage to load from
    # @return [KNN] The loaded classifier
    #
    # @rbs (storage: Storage::Base) -> KNN
    def self.load(storage:)
      data = storage.read
      raise StorageError, 'No saved state found' unless data

      instance = from_json(data)
      instance.storage = storage
      instance
    end

    # Loads a classifier from a file.
    #
    # @param path [String] The file path
    # @return [KNN] The loaded classifier
    #
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

    private

    # Finds the k nearest neighbors for the given text.
    #
    # @rbs (String) -> Array[Hash[Symbol, untyped]]
    def find_neighbors(text)
      # LSI requires at least 2 items to build an index
      # For single item, return it directly with a default similarity
      if @lsi.items.size == 1
        item = @lsi.items.first
        return [{
          item: item,
          category: @lsi.categories_for(item).first,
          similarity: 1.0
        }]
      end

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

    # Tallies votes from neighbors, optionally weighted by similarity.
    #
    # @rbs (Array[Hash[Symbol, untyped]]) -> Hash[String | Symbol, Float]
    def tally_votes(neighbors)
      votes = Hash.new(0.0)

      neighbors.each do |neighbor|
        category = neighbor[:category]
        next unless category

        weight = @weighted ? [neighbor[:similarity], 0.0].max : 1.0
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

    # Restores state from JSON (used by reload).
    #
    # @rbs (String) -> void
    def restore_from_json(json)
      data = JSON.parse(json)
      raise ArgumentError, "Invalid classifier type: #{data['type']}" unless data['type'] == 'knn'

      synchronize do
        @k = data['k']
        @weighted = data['weighted']

        lsi_data = data['lsi']
        lsi_data['type'] = 'lsi'
        @lsi = LSI.from_json(lsi_data)
        @dirty = false
      end
    end
  end
end
