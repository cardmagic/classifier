require_relative '../test_helper'

class TFIDFTest < Minitest::Test
  def setup
    @doc1 = 'Dogs are great pets and very loyal'
    @doc2 = 'Cats are independent and self-sufficient'
    @doc3 = 'Birds can fly and sing beautiful songs'
    @doc4 = 'Dogs and cats are popular pets'
    @corpus = [@doc1, @doc2, @doc3, @doc4]
  end

  # Initialization tests

  def test_default_initialization
    tfidf = Classifier::TFIDF.new

    refute_predicate tfidf, :fitted?
    assert_empty tfidf.vocabulary
    assert_empty tfidf.idf
    assert_equal 0, tfidf.num_documents
  end

  def test_custom_min_df_integer
    tfidf = Classifier::TFIDF.new(min_df: 2)

    tfidf.fit(@corpus)

    # Terms appearing in only 1 document should be excluded
    tfidf.vocabulary.each_key do |term|
      doc_count = @corpus.count { |doc| doc.clean_word_hash.key?(term) }
      assert_operator doc_count, :>=, 2, "Term #{term} should appear in at least 2 documents"
    end
  end

  def test_custom_min_df_float
    tfidf = Classifier::TFIDF.new(min_df: 0.5)

    tfidf.fit(@corpus)

    # Terms appearing in less than 50% of documents should be excluded
    min_count = (@corpus.size * 0.5).ceil
    tfidf.vocabulary.each_key do |term|
      doc_count = @corpus.count { |doc| doc.clean_word_hash.key?(term) }
      assert_operator doc_count, :>=, min_count
    end
  end

  def test_custom_max_df_integer
    tfidf = Classifier::TFIDF.new(max_df: 2)

    tfidf.fit(@corpus)

    # Terms appearing in more than 2 documents should be excluded
    tfidf.vocabulary.each_key do |term|
      doc_count = @corpus.count { |doc| doc.clean_word_hash.key?(term) }
      assert_operator doc_count, :<=, 2
    end
  end

  def test_custom_max_df_float
    tfidf = Classifier::TFIDF.new(max_df: 0.5)

    tfidf.fit(@corpus)

    # Terms appearing in more than 50% of documents should be excluded
    max_count = (@corpus.size * 0.5).floor
    tfidf.vocabulary.each_key do |term|
      doc_count = @corpus.count { |doc| doc.clean_word_hash.key?(term) }
      assert_operator doc_count, :<=, max_count
    end
  end

  def test_invalid_min_df_raises
    assert_raises(ArgumentError) { Classifier::TFIDF.new(min_df: -1) }
    assert_raises(ArgumentError) { Classifier::TFIDF.new(min_df: 1.5) }
    assert_raises(ArgumentError) { Classifier::TFIDF.new(min_df: 'invalid') }
  end

  def test_invalid_max_df_raises
    assert_raises(ArgumentError) { Classifier::TFIDF.new(max_df: -1) }
    assert_raises(ArgumentError) { Classifier::TFIDF.new(max_df: 1.5) }
    assert_raises(ArgumentError) { Classifier::TFIDF.new(max_df: 'invalid') }
  end

  def test_invalid_ngram_range_raises
    assert_raises(ArgumentError) { Classifier::TFIDF.new(ngram_range: [2, 1]) }
    assert_raises(ArgumentError) { Classifier::TFIDF.new(ngram_range: [0, 1]) }
    assert_raises(ArgumentError) { Classifier::TFIDF.new(ngram_range: [1]) }
    assert_raises(ArgumentError) { Classifier::TFIDF.new(ngram_range: 'invalid') }
  end

  # Fit tests

  def test_fit_builds_vocabulary
    tfidf = Classifier::TFIDF.new

    tfidf.fit(@corpus)

    assert_predicate tfidf, :fitted?
    refute_empty tfidf.vocabulary
    assert_equal @corpus.size, tfidf.num_documents
  end

  def test_fit_computes_idf
    tfidf = Classifier::TFIDF.new

    tfidf.fit(@corpus)

    refute_empty tfidf.idf
    assert_equal tfidf.vocabulary.size, tfidf.idf.size

    # All IDF values should be positive
    tfidf.idf.each_value do |idf_value|
      assert_operator idf_value, :>, 0
    end
  end

  def test_fit_idf_ordering
    # Terms appearing in fewer documents should have higher IDF
    docs = [
      'apple banana cherry',
      'apple banana date',
      'apple elderberry fig'
    ]
    tfidf = Classifier::TFIDF.new

    tfidf.fit(docs)

    # 'appl' appears in all 3 docs, 'banana' in 2, others in 1
    # IDF should be: rare terms > common terms
    assert_operator tfidf.idf[:elderberri], :>, tfidf.idf[:banana]
    assert_operator tfidf.idf[:banana], :>, tfidf.idf[:appl]
  end

  def test_fit_returns_self
    tfidf = Classifier::TFIDF.new

    result = tfidf.fit(@corpus)

    assert_same tfidf, result
  end

  def test_fit_with_empty_array_raises
    tfidf = Classifier::TFIDF.new

    assert_raises(ArgumentError) { tfidf.fit([]) }
  end

  def test_fit_with_non_array_raises
    tfidf = Classifier::TFIDF.new

    assert_raises(ArgumentError) { tfidf.fit('not an array') }
  end

  # Transform tests

  def test_transform_returns_tfidf_vector
    tfidf = Classifier::TFIDF.new
    tfidf.fit(@corpus)

    vector = tfidf.transform('Dogs are loyal pets')

    assert_instance_of Hash, vector
    refute_empty vector
    vector.each_value { |v| assert_kind_of Float, v }
  end

  def test_transform_before_fit_raises
    tfidf = Classifier::TFIDF.new

    assert_raises(Classifier::NotFittedError) { tfidf.transform('Some text') }
  end

  def test_transform_normalizes_vector
    tfidf = Classifier::TFIDF.new
    tfidf.fit(@corpus)

    vector = tfidf.transform('Dogs are loyal pets')

    # L2 norm should be 1 (or close to it due to floating point)
    magnitude = Math.sqrt(vector.values.sum { |v| v * v })
    assert_in_delta 1.0, magnitude, 0.0001
  end

  def test_transform_unknown_terms_ignored
    tfidf = Classifier::TFIDF.new
    tfidf.fit(['apple banana', 'cherry date'])

    # 'xyz' is not in vocabulary
    vector = tfidf.transform('apple xyz')

    refute vector.key?(:xyz)
    assert vector.key?(:appl)
  end

  def test_transform_empty_result_for_unknown_text
    tfidf = Classifier::TFIDF.new
    tfidf.fit(['apple banana', 'cherry date'])

    vector = tfidf.transform('xyz uvw')

    assert_empty vector
  end

  # fit_transform tests

  def test_fit_transform
    tfidf = Classifier::TFIDF.new

    vectors = tfidf.fit_transform(@corpus)

    assert_predicate tfidf, :fitted?
    assert_equal @corpus.size, vectors.size
    vectors.each { |v| assert_instance_of Hash, v }
  end

  # Sublinear TF tests

  def test_sublinear_tf
    # Create document with repeated term
    doc_with_repeats = 'dog dog dog dog cat'
    corpus = [doc_with_repeats, 'bird fish']

    tfidf_linear = Classifier::TFIDF.new(sublinear_tf: false)
    tfidf_sublinear = Classifier::TFIDF.new(sublinear_tf: true)

    tfidf_linear.fit(corpus)
    tfidf_sublinear.fit(corpus)

    vec_linear = tfidf_linear.transform(doc_with_repeats)
    vec_sublinear = tfidf_sublinear.transform(doc_with_repeats)

    # With sublinear TF, the ratio of dog to cat should be smaller
    # because 1 + log(4) < 4 (relative to 1 + log(1) = 1)
    ratio_linear = vec_linear[:dog] / vec_linear[:cat]
    ratio_sublinear = vec_sublinear[:dog] / vec_sublinear[:cat]

    assert_operator ratio_sublinear, :<, ratio_linear
  end

  # N-gram tests

  def test_bigrams
    tfidf = Classifier::TFIDF.new(ngram_range: [1, 2])

    tfidf.fit(['quick brown fox', 'lazy brown dog'])

    # Should have bigrams in vocabulary
    bigram_terms = tfidf.vocabulary.keys.select { |t| t.to_s.include?('_') }
    refute_empty bigram_terms, 'Should have bigram terms'
  end

  def test_bigrams_only
    tfidf = Classifier::TFIDF.new(ngram_range: [2, 2])

    tfidf.fit(['quick brown fox', 'lazy brown dog'])

    # Should only have bigrams (terms with underscore)
    tfidf.vocabulary.each_key do |term|
      assert term.to_s.include?('_'), "Term #{term} should be a bigram"
    end
  end

  def test_trigrams
    tfidf = Classifier::TFIDF.new(ngram_range: [1, 3])

    tfidf.fit(['quick brown fox jumps', 'lazy brown dog runs'])

    trigram_terms = tfidf.vocabulary.keys.select { |t| t.to_s.count('_') == 2 }
    refute_empty trigram_terms, 'Should have trigram terms'
  end

  # feature_names tests

  def test_feature_names
    tfidf = Classifier::TFIDF.new
    tfidf.fit(@corpus)

    names = tfidf.feature_names

    assert_instance_of Array, names
    assert_equal tfidf.vocabulary.size, names.size
    names.each { |n| assert_instance_of Symbol, n }
  end

  # Serialization tests

  def test_as_json
    tfidf = Classifier::TFIDF.new(min_df: 2, sublinear_tf: true)
    tfidf.fit(@corpus)

    data = tfidf.as_json

    assert_equal 1, data[:version]
    assert_equal 'tfidf', data[:type]
    assert_equal 2, data[:min_df]
    assert data[:sublinear_tf]
    assert data[:fitted]
    refute_empty data[:vocabulary]
    refute_empty data[:idf]
  end

  def test_to_json
    tfidf = Classifier::TFIDF.new
    tfidf.fit(@corpus)

    json = tfidf.to_json
    data = JSON.parse(json)

    assert_equal 'tfidf', data['type']
    assert data['fitted']
  end

  def test_from_json_string
    tfidf = Classifier::TFIDF.new(min_df: 2, sublinear_tf: true)
    tfidf.fit(@corpus)

    json = tfidf.to_json
    loaded = Classifier::TFIDF.from_json(json)

    assert_predicate loaded, :fitted?
    assert_equal tfidf.vocabulary.size, loaded.vocabulary.size
    assert_equal tfidf.num_documents, loaded.num_documents

    # Transform should produce same results
    original_vec = tfidf.transform('Dogs are great')
    loaded_vec = loaded.transform('Dogs are great')
    assert_equal original_vec, loaded_vec
  end

  def test_from_json_hash
    tfidf = Classifier::TFIDF.new
    tfidf.fit(@corpus)

    hash = JSON.parse(tfidf.to_json)
    loaded = Classifier::TFIDF.from_json(hash)

    assert_predicate loaded, :fitted?
    assert_equal tfidf.vocabulary.size, loaded.vocabulary.size
  end

  def test_from_json_invalid_type_raises
    invalid_json = { version: 1, type: 'invalid' }.to_json

    assert_raises(ArgumentError) { Classifier::TFIDF.from_json(invalid_json) }
  end

  # Marshal tests

  def test_marshal_dump_load
    tfidf = Classifier::TFIDF.new(min_df: 2, sublinear_tf: true)
    tfidf.fit(@corpus)

    dumped = Marshal.dump(tfidf)
    loaded = Marshal.load(dumped) # rubocop:disable Security/MarshalLoad

    assert_predicate loaded, :fitted?
    assert_equal tfidf.vocabulary, loaded.vocabulary
    assert_equal tfidf.idf, loaded.idf

    # Transform should produce same results
    original_vec = tfidf.transform('Dogs are great')
    loaded_vec = loaded.transform('Dogs are great')
    assert_equal original_vec, loaded_vec
  end

  # Edge cases

  def test_single_document_corpus
    tfidf = Classifier::TFIDF.new

    tfidf.fit(['Single document with words'])

    assert_predicate tfidf, :fitted?
    refute_empty tfidf.vocabulary
  end

  def test_document_with_only_stopwords
    tfidf = Classifier::TFIDF.new
    tfidf.fit(['the and or but', 'dog cat bird'])

    # Transform a document with only stopwords
    vector = tfidf.transform('the and or but')

    assert_empty vector
  end

  def test_repeated_fit_overwrites
    tfidf = Classifier::TFIDF.new

    tfidf.fit(['apple banana'])
    first_vocab = tfidf.vocabulary.dup

    tfidf.fit(['cherry date elderberry'])

    refute_equal first_vocab, tfidf.vocabulary
  end

  def test_unicode_text
    tfidf = Classifier::TFIDF.new

    tfidf.fit(['Caf manger boire', 'chteau jardin maison'])
    vector = tfidf.transform('Caf jardin')

    refute_empty vector
  end

  def test_very_long_document
    long_doc = (['word'] * 1000).join(' ')
    tfidf = Classifier::TFIDF.new

    tfidf.fit([long_doc, 'short document'])
    vector = tfidf.transform(long_doc)

    refute_empty vector
    # Should still be normalized
    magnitude = Math.sqrt(vector.values.sum { |v| v * v })
    assert_in_delta 1.0, magnitude, 0.0001 unless vector.empty?
  end

  def test_empty_document_in_corpus
    # Empty strings should not cause issues
    tfidf = Classifier::TFIDF.new

    tfidf.fit(['dog cat', '', 'bird fish'])

    assert_predicate tfidf, :fitted?
    assert_equal 3, tfidf.num_documents
  end
end
