# rbs_inline: enabled

# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2024 Lucas Carlson
# License::   LGPL

require 'json'

module Classifier
  # TF-IDF vectorizer: transforms text to weighted feature vectors.
  # Downweights common words, upweights discriminative terms.
  #
  # Example:
  #   tfidf = Classifier::TFIDF.new
  #   tfidf.fit(["Dogs are great pets", "Cats are independent"])
  #   tfidf.transform("Dogs are loyal")  # => {:dog=>0.7071..., :loyal=>0.7071...}
  #
  class TFIDF
    include Streaming

    # @rbs @min_df: Integer | Float
    # @rbs @max_df: Integer | Float
    # @rbs @ngram_range: Array[Integer]
    # @rbs @sublinear_tf: bool
    # @rbs @vocabulary: Hash[Symbol, Integer]
    # @rbs @idf: Hash[Symbol, Float]
    # @rbs @num_documents: Integer
    # @rbs @fitted: bool
    # @rbs @dirty: bool
    # @rbs @storage: Storage::Base?

    attr_reader :vocabulary, :idf, :num_documents
    attr_accessor :storage

    # Creates a new TF-IDF vectorizer.
    # - min_df/max_df: filter terms by document frequency (Integer for count, Float for proportion)
    # - ngram_range: [1,1] for unigrams, [1,2] for unigrams+bigrams
    # - sublinear_tf: use 1 + log(tf) instead of raw term frequency
    #
    # @rbs (?min_df: Integer | Float, ?max_df: Integer | Float,
    #       ?ngram_range: Array[Integer], ?sublinear_tf: bool) -> void
    def initialize(min_df: 1, max_df: 1.0, ngram_range: [1, 1], sublinear_tf: false)
      validate_df!(min_df, 'min_df')
      validate_df!(max_df, 'max_df')
      validate_ngram_range!(ngram_range)

      @min_df = min_df
      @max_df = max_df
      @ngram_range = ngram_range
      @sublinear_tf = sublinear_tf
      @vocabulary = {}
      @idf = {}
      @num_documents = 0
      @fitted = false
      @dirty = false
      @storage = nil
    end

    # Learns vocabulary and IDF weights from the corpus.
    # @rbs (Array[String]) -> self
    def fit(documents)
      raise ArgumentError, 'documents must be an array' unless documents.is_a?(Array)
      raise ArgumentError, 'documents cannot be empty' if documents.empty?

      @num_documents = documents.size
      document_frequencies = Hash.new(0)

      documents.each do |doc|
        terms = extract_terms(doc)
        terms.each_key { |term| document_frequencies[term] += 1 }
      end

      @vocabulary = {}
      @idf = {}
      vocab_index = 0

      document_frequencies.each do |term, df|
        next unless within_df_bounds?(df, @num_documents)

        @vocabulary[term] = vocab_index
        vocab_index += 1

        # IDF: log((N + 1) / (df + 1)) + 1
        @idf[term] = Math.log((@num_documents + 1).to_f / (df + 1)) + 1
      end

      @fitted = true
      @dirty = true
      self
    end

    # Transforms a document into a normalized TF-IDF vector.
    # @rbs (String) -> Hash[Symbol, Float]
    def transform(document)
      raise NotFittedError, 'TFIDF has not been fitted. Call fit first.' unless @fitted

      terms = extract_terms(document)
      result = {} #: Hash[Symbol, Float]

      terms.each do |term, tf|
        next unless @vocabulary.key?(term)

        tf_value = @sublinear_tf && tf.positive? ? 1 + Math.log(tf) : tf.to_f
        result[term] = (tf_value * @idf[term]).to_f
      end

      normalize_vector(result)
    end

    # Fits and transforms in one step.
    # @rbs (Array[String]) -> Array[Hash[Symbol, Float]]
    def fit_transform(documents)
      fit(documents)
      documents.map { |doc| transform(doc) }
    end

    # Returns vocabulary terms in index order.
    # @rbs () -> Array[Symbol]
    def feature_names
      @vocabulary.keys.sort_by { |term| @vocabulary[term] }
    end

    # @rbs () -> bool
    def fitted?
      @fitted
    end

    # Returns true if there are unsaved changes.
    # @rbs () -> bool
    def dirty?
      @dirty
    end

    # Saves the vectorizer to the configured storage.
    # @rbs () -> void
    def save
      raise ArgumentError, 'No storage configured' unless storage

      storage.write(to_json)
      @dirty = false
    end

    # Saves the vectorizer state to a file.
    # @rbs (String) -> Integer
    def save_to_file(path)
      result = File.write(path, to_json)
      @dirty = false
      result
    end

    # Loads a vectorizer from the configured storage.
    # @rbs (storage: Storage::Base) -> TFIDF
    def self.load(storage:)
      data = storage.read
      raise StorageError, 'No saved state found' unless data

      instance = from_json(data)
      instance.storage = storage
      instance
    end

    # Loads a vectorizer from a file.
    # @rbs (String) -> TFIDF
    def self.load_from_file(path)
      from_json(File.read(path))
    end

    # Reloads the vectorizer from storage, raising if there are unsaved changes.
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

    # Force reloads the vectorizer from storage, discarding any unsaved changes.
    # @rbs () -> self
    def reload!
      raise ArgumentError, 'No storage configured' unless storage

      data = storage.read
      raise StorageError, 'No saved state found' unless data

      restore_from_json(data)
      @dirty = false
      self
    end

    # @rbs (?untyped) -> Hash[Symbol, untyped]
    def as_json(_options = nil)
      {
        version: 1,
        type: 'tfidf',
        min_df: @min_df,
        max_df: @max_df,
        ngram_range: @ngram_range,
        sublinear_tf: @sublinear_tf,
        vocabulary: @vocabulary,
        idf: @idf,
        num_documents: @num_documents,
        fitted: @fitted
      }
    end

    # @rbs (?untyped) -> String
    def to_json(_options = nil)
      JSON.generate(as_json)
    end

    # Loads a vectorizer from JSON.
    # @rbs (String | Hash[String, untyped]) -> TFIDF
    def self.from_json(json)
      data = json.is_a?(String) ? JSON.parse(json) : json
      raise ArgumentError, "Invalid vectorizer type: #{data['type']}" unless data['type'] == 'tfidf'

      instance = new(
        min_df: data['min_df'],
        max_df: data['max_df'],
        ngram_range: data['ngram_range'],
        sublinear_tf: data['sublinear_tf']
      )

      instance.instance_variable_set(:@vocabulary, symbolize_keys(data['vocabulary']))
      instance.instance_variable_set(:@idf, symbolize_keys(data['idf']))
      instance.instance_variable_set(:@num_documents, data['num_documents'])
      instance.instance_variable_set(:@fitted, data['fitted'])
      instance.instance_variable_set(:@dirty, false)
      instance.instance_variable_set(:@storage, nil)

      instance
    end

    # @rbs () -> Array[untyped]
    def marshal_dump
      [@min_df, @max_df, @ngram_range, @sublinear_tf, @vocabulary, @idf, @num_documents, @fitted]
    end

    # @rbs (Array[untyped]) -> void
    def marshal_load(data)
      @min_df, @max_df, @ngram_range, @sublinear_tf, @vocabulary, @idf, @num_documents, @fitted = data
      @dirty = false
      @storage = nil
    end

    # Loads a vectorizer from a checkpoint.
    #
    # @rbs (storage: Storage::Base, checkpoint_id: String) -> TFIDF
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

    # Fits the vectorizer from an IO stream.
    # Collects all documents from the stream, then fits the model.
    # Note: All documents must be collected in memory for IDF calculation.
    #
    # @example Fit from a file
    #   tfidf.fit_from_stream(File.open('corpus.txt'))
    #
    # @example With progress tracking
    #   tfidf.fit_from_stream(io, batch_size: 500) do |progress|
    #     puts "#{progress.completed} documents loaded"
    #   end
    #
    # @rbs (IO, ?batch_size: Integer) { (Streaming::Progress) -> void } -> self
    def fit_from_stream(io, batch_size: Streaming::DEFAULT_BATCH_SIZE)
      reader = Streaming::LineReader.new(io, batch_size: batch_size)
      total = reader.estimate_line_count
      progress = Streaming::Progress.new(total: total)

      documents = [] #: Array[String]

      reader.each_batch do |batch|
        documents.concat(batch)
        progress.completed += batch.size
        progress.current_batch += 1
        yield progress if block_given?
      end

      fit(documents) unless documents.empty?
      self
    end

    # TFIDF doesn't support train_from_stream (use fit_from_stream instead).
    # This method raises NotImplementedError with guidance.
    #
    # @rbs (*untyped, **untyped) -> void
    def train_from_stream(*) # steep:ignore
      raise NotImplementedError, 'TFIDF uses fit_from_stream instead of train_from_stream'
    end

    # TFIDF doesn't support train_batch (use fit instead).
    # This method raises NotImplementedError with guidance.
    #
    # @rbs (*untyped, **untyped) -> void
    def train_batch(*) # steep:ignore
      raise NotImplementedError, 'TFIDF uses fit instead of train_batch'
    end

    private

    # Restores vectorizer state from JSON string.
    # @rbs (String) -> void
    def restore_from_json(json)
      data = JSON.parse(json)

      @min_df = data['min_df']
      @max_df = data['max_df']
      @ngram_range = data['ngram_range']
      @sublinear_tf = data['sublinear_tf']
      @vocabulary = self.class.send(:symbolize_keys, data['vocabulary'])
      @idf = self.class.send(:symbolize_keys, data['idf'])
      @num_documents = data['num_documents']
      @fitted = data['fitted']
    end

    # @rbs (String) -> Hash[Symbol, Integer]
    def extract_terms(document)
      result = Hash.new(0)

      if @ngram_range[0] <= 1
        word_hash = document.clean_word_hash
        word_hash.each { |term, count| result[term] += count }
      end

      return result if @ngram_range[1] <= 1

      tokens = tokenize_for_ngrams(document)
      (2..@ngram_range[1]).each do |n|
        next if n < @ngram_range[0]

        generate_ngrams(tokens, n).each { |ngram| result[ngram] += 1 }
      end

      result
    end

    # @rbs (String) -> Array[String]
    def tokenize_for_ngrams(document)
      document
        .gsub(/[^\w\s]/, '')
        .split
        .map(&:downcase)
        .reject { |w| w.length <= 2 || String::CORPUS_SKIP_WORDS.include?(w) }
        .map(&:stem)
    end

    # @rbs (Array[String], Integer) -> Array[Symbol]
    def generate_ngrams(tokens, n) # rubocop:disable Naming/MethodParameterName
      return [] if tokens.size < n

      tokens.each_cons(n).map { |gram| gram.join('_').intern }
    end

    # @rbs (Integer, Integer) -> bool
    def within_df_bounds?(doc_freq, num_docs)
      doc_freq.between?(
        @min_df.is_a?(Float) ? (@min_df * num_docs).ceil : @min_df,
        @max_df.is_a?(Float) ? (@max_df * num_docs).floor : @max_df
      )
    end

    # @rbs (Hash[Symbol, Float]) -> Hash[Symbol, Float]
    def normalize_vector(vector)
      return vector if vector.empty?

      magnitude = Math.sqrt(vector.values.sum { |v| v * v })
      return vector if magnitude.zero?

      vector.transform_values { |v| v / magnitude }
    end

    # @rbs (Integer | Float, String) -> void
    def validate_df!(value, name)
      raise ArgumentError, "#{name} must be an Integer or Float" unless value.is_a?(Float) || value.is_a?(Integer)
      raise ArgumentError, "#{name} must be between 0.0 and 1.0" if value.is_a?(Float) && !value.between?(0.0, 1.0)
      raise ArgumentError, "#{name} must be non-negative" if value.is_a?(Integer) && value.negative?
    end

    # @rbs (Array[Integer]) -> void
    def validate_ngram_range!(range)
      raise ArgumentError, 'ngram_range must be an array of two integers' unless range.is_a?(Array) && range.size == 2
      raise ArgumentError, 'ngram_range values must be positive integers' unless range.all?(Integer) && range.all?(&:positive?)
      raise ArgumentError, 'ngram_range[0] must be <= ngram_range[1]' if range[0] > range[1]
    end

    # @rbs (Hash[String, untyped]) -> Hash[Symbol, untyped]
    def self.symbolize_keys(hash)
      hash.transform_keys(&:to_sym)
    end
    private_class_method :symbolize_keys
  end
end
