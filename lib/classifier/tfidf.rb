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
    # @rbs @min_df: Integer | Float
    # @rbs @max_df: Integer | Float
    # @rbs @ngram_range: Array[Integer]
    # @rbs @sublinear_tf: bool
    # @rbs @vocabulary: Hash[Symbol, Integer]
    # @rbs @idf: Hash[Symbol, Float]
    # @rbs @num_documents: Integer
    # @rbs @fitted: bool

    attr_reader :vocabulary, :idf, :num_documents

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

        # IDF: log((N + 1) / (df + 1)) + 1 with smoothing
        @idf[term] = Math.log((@num_documents + 1).to_f / (df + 1)) + 1
      end

      @fitted = true
      self
    end

    # Transforms a document into a normalized TF-IDF vector.
    # @rbs (String) -> Hash[Symbol, Float]
    def transform(document)
      raise NotFittedError, 'TFIDF has not been fitted. Call fit first.' unless @fitted

      terms = extract_terms(document)
      result = {}

      terms.each do |term, tf|
        next unless @vocabulary.key?(term)

        tf_value = @sublinear_tf && tf.positive? ? 1 + Math.log(tf) : tf.to_f
        result[term] = tf_value * @idf[term]
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
      as_json.to_json
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

      instance
    end

    # @rbs () -> Array[untyped]
    def marshal_dump
      [@min_df, @max_df, @ngram_range, @sublinear_tf, @vocabulary, @idf, @num_documents, @fitted]
    end

    # @rbs (Array[untyped]) -> void
    def marshal_load(data)
      @min_df, @max_df, @ngram_range, @sublinear_tf, @vocabulary, @idf, @num_documents, @fitted = data
    end

    private

    # @rbs (String) -> Hash[Symbol, Integer]
    def extract_terms(document)
      result = Hash.new(0)

      if @ngram_range[0] <= 1
        word_hash = document.clean_word_hash
        word_hash.each { |term, count| result[term] += count }
      end

      if @ngram_range[1] > 1
        tokens = tokenize_for_ngrams(document)
        (2..@ngram_range[1]).each do |n|
          next if n < @ngram_range[0]

          generate_ngrams(tokens, n).each { |ngram| result[ngram] += 1 }
        end
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
      min_count = @min_df.is_a?(Float) ? (@min_df * num_docs).ceil : @min_df
      max_count = @max_df.is_a?(Float) ? (@max_df * num_docs).floor : @max_df

      doc_freq.between?(min_count, max_count)
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
      if value.is_a?(Float)
        raise ArgumentError, "#{name} must be between 0.0 and 1.0" unless value.between?(0.0, 1.0)
      elsif value.is_a?(Integer)
        raise ArgumentError, "#{name} must be non-negative" if value.negative?
      else
        raise ArgumentError, "#{name} must be an Integer or Float"
      end
    end

    # @rbs (Array[Integer]) -> void
    def validate_ngram_range!(range)
      valid_structure = range.is_a?(Array) && range.size == 2
      raise ArgumentError, 'ngram_range must be an array of two integers' unless valid_structure

      valid_values = range.all? { |v| v.is_a?(Integer) && v.positive? }
      raise ArgumentError, 'ngram_range values must be positive integers' unless valid_values

      raise ArgumentError, 'ngram_range[0] must be <= ngram_range[1]' if range[0] > range[1]
    end

    # @rbs (Hash[String, untyped]) -> Hash[Symbol, untyped]
    def self.symbolize_keys(hash)
      hash.transform_keys(&:to_sym)
    end
    private_class_method :symbolize_keys
  end
end
