# rbs_inline: enabled

# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2005 Lucas Carlson
# License::   LGPL

require 'json'
require 'mutex_m'

module Classifier
  class Bayes
    include Mutex_m

    # @rbs @categories: Hash[Symbol, Hash[Symbol, Integer]]
    # @rbs @total_words: Integer
    # @rbs @category_counts: Hash[Symbol, Integer]
    # @rbs @category_word_count: Hash[Symbol, Integer]
    # @rbs @cached_training_count: Float?
    # @rbs @cached_vocab_size: Integer?
    # @rbs @dirty: bool
    # @rbs @storage: Storage::Base?

    attr_accessor :storage

    # The class can be created with one or more categories, each of which will be
    # initialized and given a training method. E.g.,
    #      b = Classifier::Bayes.new 'Interesting', 'Uninteresting', 'Spam'
    # @rbs (*String | Symbol) -> void
    def initialize(*categories)
      super()
      @categories = {}
      categories.each { |category| @categories[category.prepare_category_name] = {} }
      @total_words = 0
      @category_counts = Hash.new(0)
      @category_word_count = Hash.new(0)
      @cached_training_count = nil
      @cached_vocab_size = nil
      @dirty = false
      @storage = nil
    end

    # Provides a general training method for all categories specified in Bayes#new
    # For example:
    #     b = Classifier::Bayes.new :spam, :ham
    #
    #     # Keyword argument API (preferred)
    #     b.train(spam: "Buy cheap viagra now!!!")
    #     b.train(spam: ["msg1", "msg2"], ham: ["msg3", "msg4"])
    #
    #     # Positional argument API (legacy)
    #     b.train :spam, "This text"
    #     b.train "ham", "That text"
    #
    # @rbs (?String | Symbol, ?String, **String | Array[String]) -> void
    def train(category = nil, text = nil, **categories)
      return train_single(category, text) if category

      categories.each do |cat, texts|
        Array(texts).each { |t| train_single(cat, t) }
      end
    end

    # Provides a untraining method for all categories specified in Bayes#new
    # Be very careful with this method.
    #
    # For example:
    #     b = Classifier::Bayes.new :spam, :ham
    #
    #     # Keyword argument API (preferred)
    #     b.train(spam: "Buy cheap viagra now!!!")
    #     b.untrain(spam: "Buy cheap viagra now!!!")
    #
    #     # Positional argument API (legacy)
    #     b.train :spam, "This text"
    #     b.untrain :spam, "This text"
    #
    # @rbs (?String | Symbol, ?String, **String | Array[String]) -> void
    def untrain(category = nil, text = nil, **categories)
      return untrain_single(category, text) if category

      categories.each do |cat, texts|
        Array(texts).each { |t| untrain_single(cat, t) }
      end
    end

    # Returns the scores in each category the provided +text+. E.g.,
    #    b.classifications "I hate bad words and you"
    #    =>  {"Uninteresting"=>-12.6997928013932, "Interesting"=>-18.4206807439524}
    # The largest of these scores (the one closest to 0) is the one picked out by #classify
    #
    # @rbs (String) -> Hash[String, Float]
    def classifications(text)
      words = text.word_hash.keys
      synchronize do
        training_count = cached_training_count
        vocab_size = cached_vocab_size

        @categories.to_h do |category, category_words|
          smoothed_total = ((@category_word_count[category] || 0) + vocab_size).to_f

          # Laplace smoothing: P(word|category) = (count + α) / (total + α * V)
          word_score = words.sum { |w| Math.log(((category_words[w] || 0) + 1) / smoothed_total) }
          prior_score = Math.log((@category_counts[category] || 0.1) / training_count)

          [category.to_s, word_score + prior_score]
        end
      end
    end

    # Returns the classification of the provided +text+, which is one of the
    # categories given in the initializer. E.g.,
    #    b.classify "I hate bad words and you"
    #    =>  'Uninteresting'
    #
    # @rbs (String) -> String
    def classify(text)
      best = classifications(text).min_by { |a| -a[1] }
      raise StandardError, 'No classifications available' unless best

      best.first.to_s
    end

    # Returns a hash representation of the classifier state.
    # This can be converted to JSON or used directly.
    #
    # @rbs () -> untyped
    def as_json(*)
      {
        version: 1,
        type: 'bayes',
        categories: @categories.transform_keys(&:to_s).transform_values { |v| v.transform_keys(&:to_s) },
        total_words: @total_words,
        category_counts: @category_counts.transform_keys(&:to_s),
        category_word_count: @category_word_count.transform_keys(&:to_s)
      }
    end

    # Serializes the classifier state to a JSON string.
    # This can be saved to a file and later loaded with Bayes.from_json.
    #
    # @rbs () -> String
    def to_json(*)
      as_json.to_json
    end

    # Loads a classifier from a JSON string or a Hash created by #to_json or #as_json.
    #
    # @rbs (String | Hash[String, untyped]) -> Bayes
    def self.from_json(json)
      data = json.is_a?(String) ? JSON.parse(json) : json
      raise ArgumentError, "Invalid classifier type: #{data['type']}" unless data['type'] == 'bayes'

      instance = allocate
      instance.send(:restore_state, data)
      instance
    end

    # Saves the classifier to the configured storage.
    # Raises ArgumentError if no storage is configured.
    #
    # @rbs () -> void
    def save
      raise ArgumentError, 'No storage configured. Use save_to_file(path) or set storage=' unless storage

      storage.write(to_json)
      @dirty = false
    end

    # Saves the classifier state to a file (legacy API).
    #
    # @rbs (String) -> Integer
    def save_to_file(path)
      result = File.write(path, to_json)
      @dirty = false
      result
    end

    # Reloads the classifier from the configured storage.
    # Raises UnsavedChangesError if there are unsaved changes.
    # Use reload! to force reload and discard changes.
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

    # Returns true if there are unsaved changes.
    #
    # @rbs () -> bool
    def dirty?
      @dirty
    end

    # Loads a classifier from the configured storage.
    # The storage is set on the returned instance.
    #
    # @rbs (storage: Storage::Base) -> Bayes
    def self.load(storage:)
      data = storage.read
      raise StorageError, 'No saved state found' unless data

      instance = from_json(data)
      instance.storage = storage
      instance
    end

    # Loads a classifier from a file (legacy API).
    #
    # @rbs (String) -> Bayes
    def self.load_from_file(path)
      from_json(File.read(path))
    end

    #
    # Provides training and untraining methods for the categories specified in Bayes#new
    # For example:
    #     b = Classifier::Bayes.new 'This', 'That', 'the_other'
    #     b.train_this "This text"
    #     b.train_that "That text"
    #     b.untrain_that "That text"
    #     b.train_the_other "The other text"
    def method_missing(name, *args)
      return super unless name.to_s =~ /(un)?train_(\w+)/

      category = name.to_s.gsub(/(un)?train_(\w+)/, '\2').prepare_category_name
      raise StandardError, "No such category: #{category}" unless @categories.key?(category)

      method = name.to_s.start_with?('untrain_') ? :untrain : :train
      args.each { |text| send(method, category, text) }
    end

    # @rbs (Symbol, ?bool) -> bool
    def respond_to_missing?(name, include_private = false)
      !!(name.to_s =~ /(un)?train_(\w+)/) || super
    end

    # Provides a list of category names
    # For example:
    #     b.categories
    #     =>   ['This', 'That', 'the_other']
    #
    # @rbs () -> Array[String]
    def categories
      synchronize { @categories.keys.collect(&:to_s) }
    end

    # Allows you to add categories to the classifier.
    # For example:
    #     b.add_category "Not spam"
    #
    # WARNING: Adding categories to a trained classifier will
    # result in an undertrained category that will tend to match
    # more criteria than the trained selective categories. In short,
    # try to initialize your categories at initialization.
    #
    # @rbs (String | Symbol) -> Hash[Symbol, Integer]
    def add_category(category)
      synchronize do
        invalidate_caches
        @dirty = true
        @categories[category.prepare_category_name] = {}
      end
    end

    alias append_category add_category

    # Custom marshal serialization to exclude mutex state
    # @rbs () -> Array[untyped]
    def marshal_dump
      [@categories, @total_words, @category_counts, @category_word_count, @dirty]
    end

    # Custom marshal deserialization to recreate mutex
    # @rbs (Array[untyped]) -> void
    def marshal_load(data)
      mu_initialize
      @categories, @total_words, @category_counts, @category_word_count, @dirty = data
      @cached_training_count = nil
      @cached_vocab_size = nil
      @storage = nil
    end

    # Allows you to remove categories from the classifier.
    # For example:
    #     b.remove_category "Spam"
    #
    # WARNING: Removing categories from a trained classifier will
    # result in the loss of all training data for that category.
    # Make sure you really want to do this before calling this method.
    #
    # @rbs (String | Symbol) -> void
    def remove_category(category)
      category = category.prepare_category_name
      synchronize do
        raise StandardError, "No such category: #{category}" unless @categories.key?(category)

        invalidate_caches
        @dirty = true
        @total_words -= @category_word_count[category].to_i

        @categories.delete(category)
        @category_counts.delete(category)
        @category_word_count.delete(category)
      end
    end

    private

    # Core training logic for a single category and text.
    # @rbs (String | Symbol, String) -> void
    def train_single(category, text)
      category = category.prepare_category_name
      word_hash = text.word_hash
      synchronize do
        invalidate_caches
        @dirty = true
        @category_counts[category] += 1
        word_hash.each do |word, count|
          @categories[category][word] ||= 0
          @categories[category][word] += count
          @total_words += count
          @category_word_count[category] += count
        end
      end
    end

    # Core untraining logic for a single category and text.
    # @rbs (String | Symbol, String) -> void
    def untrain_single(category, text)
      category = category.prepare_category_name
      word_hash = text.word_hash
      synchronize do
        invalidate_caches
        @dirty = true
        @category_counts[category] -= 1
        word_hash.each do |word, count|
          next unless @total_words >= 0

          orig = @categories[category][word] || 0
          @categories[category][word] ||= 0
          @categories[category][word] -= count
          if @categories[category][word] <= 0
            @categories[category].delete(word)
            count = orig
          end
          @category_word_count[category] -= count if @category_word_count[category] >= count
          @total_words -= count
        end
      end
    end

    # Restores classifier state from a JSON string (used by reload)
    # @rbs (String) -> void
    def restore_from_json(json)
      data = JSON.parse(json)
      raise ArgumentError, "Invalid classifier type: #{data['type']}" unless data['type'] == 'bayes'

      synchronize do
        restore_state(data)
      end
    end

    # Restores classifier state from a hash (used by from_json)
    # @rbs (Hash[String, untyped]) -> void
    def restore_state(data)
      mu_initialize
      @categories = {} #: Hash[Symbol, Hash[Symbol, Integer]]
      @total_words = data['total_words']
      @category_counts = Hash.new(0) #: Hash[Symbol, Integer]
      @category_word_count = Hash.new(0) #: Hash[Symbol, Integer]
      @cached_training_count = nil
      @cached_vocab_size = nil
      @dirty = false
      @storage = nil

      data['categories'].each do |cat_name, words|
        @categories[cat_name.to_sym] = words.transform_keys(&:to_sym)
      end

      data['category_counts'].each do |cat_name, count|
        @category_counts[cat_name.to_sym] = count
      end

      data['category_word_count'].each do |cat_name, count|
        @category_word_count[cat_name.to_sym] = count
      end
    end

    # @rbs () -> void
    def invalidate_caches
      @cached_training_count = nil
      @cached_vocab_size = nil
    end

    # @rbs () -> Float
    def cached_training_count
      @cached_training_count ||= @category_counts.values.sum.to_f
    end

    # @rbs () -> Integer
    def cached_vocab_size
      @cached_vocab_size ||= [@categories.values.flat_map(&:keys).uniq.size, 1].max
    end
  end
end
