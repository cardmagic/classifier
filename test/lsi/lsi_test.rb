require_relative '../test_helper'

class LSITest < Minitest::Test
  def setup
    # we repeat principle words to help weight them.
    # This test is rather delicate, since this system is mostly noise.
    @str1 = 'This text deals with dogs. Dogs.'
    @str2 = 'This text involves dogs too. Dogs! '
    @str3 = 'This text revolves around cats. Cats.'
    @str4 = 'This text also involves cats. Cats!'
    @str5 = 'This text involves birds. Birds.'
  end

  def test_basic_indexing
    lsi = Classifier::LSI.new
    [@str1, @str2, @str3, @str4, @str5].each { |x| lsi << x }

    refute_predicate lsi, :needs_rebuild?

    # NOTE: that the closest match to str1 is str2, even though it is not
    # the closest text match.
    assert_equal [@str2, @str5, @str3], lsi.find_related(@str1, 3)
  end

  def test_not_auto_rebuild
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'

    assert_predicate lsi, :needs_rebuild?
    lsi.build_index

    refute_predicate lsi, :needs_rebuild?
  end

  def test_basic_categorizing
    lsi = Classifier::LSI.new
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'

    assert_equal 'Dog', lsi.classify(@str1)
    assert_equal 'Cat', lsi.classify(@str3)
    assert_equal 'Bird', lsi.classify(@str5)
    assert_equal 'Bird', lsi.classify('Bird me to Bird')
  end

  def test_external_classifying
    lsi = Classifier::LSI.new
    bayes = Classifier::Bayes.new 'Dog', 'Cat', 'Bird'
    lsi.add_item @str1, 'Dog'
    bayes.train_dog @str1
    lsi.add_item @str2, 'Dog'
    bayes.train_dog @str2
    lsi.add_item @str3, 'Cat'
    bayes.train_cat @str3
    lsi.add_item @str4, 'Cat'
    bayes.train_cat @str4
    lsi.add_item @str5, 'Bird'
    bayes.train_bird @str5

    # Both classifiers should recognize this is about dogs
    tricky_case = 'This text revolves around dogs.'

    assert_equal 'Dog', lsi.classify(tricky_case)
    assert_equal 'Dog', bayes.classify(tricky_case)
  end

  def test_recategorize_interface
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'

    tricky_case = 'This text revolves around dogs.'

    assert_equal 'Dog', lsi.classify(tricky_case)

    # Recategorize as needed.
    lsi.categories_for(@str1).clear.push 'Cow'
    lsi.categories_for(@str2).clear.push 'Cow'

    refute_predicate lsi, :needs_rebuild?
    assert_equal 'Cow', lsi.classify(tricky_case)
  end

  def test_classify_with_confidence
    lsi = Classifier::LSI.new
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'

    category, confidence = lsi.classify_with_confidence(@str1)

    assert_equal 'Dog', category
    assert_operator confidence, :>, 0.5, "Confidence should be greater than 0.5, but was #{confidence}"

    category, confidence = lsi.classify_with_confidence(@str3)

    assert_equal 'Cat', category
    assert_operator confidence, :>, 0.5, "Confidence should be greater than 0.5, but was #{confidence}"

    category, confidence = lsi.classify_with_confidence(@str5)

    assert_equal 'Bird', category
    assert_operator confidence, :>, 0.5, "Confidence should be greater than 0.5, but was #{confidence}"

    tricky_case = 'This text revolves around dogs.'
    category, confidence = lsi.classify_with_confidence(tricky_case)

    assert_equal 'Dog', category
    assert_operator confidence, :>, 0.3, "Confidence should be greater than 0.3, but was #{confidence}"
  end

  def test_search
    lsi = Classifier::LSI.new
    [@str1, @str2, @str3, @str4, @str5].each { |x| lsi << x }

    # Searching by content and text - top 2 should be dog-related
    results = lsi.search('dog involves', 100)

    assert_equal Set.new([@str2, @str1]), Set.new(results.first(2)), 'Top 2 results should be dog-related'
    assert_includes [@str3, @str4], results.last, 'Least related should be cat-only text'
    assert_equal Set.new([@str1, @str2, @str3, @str4, @str5]), Set.new(results)

    # Keyword search - top 2 should be dog-related
    results = lsi.search('dog', 5)

    assert_equal Set.new([@str1, @str2]), Set.new(results.first(2)), 'Top 2 results should be dog-related'
    assert_includes [@str3, @str4], results.last, 'Least related should be cat-only text'
  end

  def test_serialize_safe
    lsi = Classifier::LSI.new
    [@str1, @str2, @str3, @str4, @str5].each { |x| lsi << x }

    lsi_md = Marshal.dump lsi
    lsi_m = Marshal.load lsi_md

    assert_equal lsi_m.search('cat', 3), lsi.search('cat', 3)
    assert_equal lsi_m.find_related(@str1, 3), lsi.find_related(@str1, 3)
  end

  def test_keyword_search
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'

    assert_equal %i[dog text deal], lsi.highest_ranked_stems(@str1)
  end

  def test_summary
    summary = [@str1, @str2, @str3, @str4, @str5].join.summary(2)
    # Summary should contain 2 sentences separated by [...]
    assert_match(/\[\.\.\.\]/, summary, 'Summary should contain [...] separator')
    parts = summary.split('[...]').map(&:strip)

    assert_equal 2, parts.size, 'Summary should have 2 parts'
    # Each part should be one of our test strings (stripped)
    all_texts = [@str1, @str2, @str3, @str4, @str5].map(&:strip)

    parts.each do |part|
      assert all_texts.any? { |t| t.include?(part.gsub('This text ', '').split.first) },
             "Summary part '#{part}' should be from test texts"
    end
  end

  # Edge case tests

  def test_empty_index_needs_rebuild
    lsi = Classifier::LSI.new

    refute_predicate lsi, :needs_rebuild?, 'Empty index should not need rebuild'
  end

  def test_single_item_needs_rebuild
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item 'Single document', 'Category'

    refute_predicate lsi, :needs_rebuild?, 'Single item index should not need rebuild'
  end

  def test_remove_item
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'

    assert_equal 2, lsi.items.size

    lsi.remove_item @str1

    assert_equal 1, lsi.items.size
    refute_includes lsi.items, @str1
  end

  def test_remove_nonexistent_item
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'

    lsi.remove_item 'nonexistent'

    assert_equal 1, lsi.items.size, 'Should not affect index when removing nonexistent item'
  end

  def test_remove_item_triggers_needs_rebuild
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.build_index

    refute_predicate lsi, :needs_rebuild?, 'Index should be current after build'

    lsi.remove_item @str1

    assert_predicate lsi, :needs_rebuild?, 'Index should need rebuild after removing item'
  end

  def test_items_method
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Cat'

    items = lsi.items

    assert_equal 2, items.size
    assert_includes items, @str1
    assert_includes items, @str2
  end

  def test_find_related_excludes_self
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    result = lsi.find_related(@str1, 3)

    refute_includes result, @str1, 'Should not include the source document in related results'
  end

  def test_unicode_mixed_with_ascii
    lsi = Classifier::LSI.new
    lsi.add_item 'English words and text here', 'English'
    lsi.add_item 'More english content available', 'English'
    lsi.add_item 'French words bonjour merci', 'French'

    result = lsi.classify('english content')

    assert_equal 'English', result
  end

  def test_needs_rebuild_with_auto_rebuild_true
    lsi = Classifier::LSI.new auto_rebuild: true
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'

    refute_predicate lsi, :needs_rebuild?, 'Auto-rebuild should keep index current'
  end

  def test_categories_for_nonexistent_item
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'

    result = lsi.categories_for('nonexistent')

    assert_empty result, 'Should return empty array for nonexistent item'
  end

  # Numerical stability tests

  def test_identical_documents
    lsi = Classifier::LSI.new auto_rebuild: false

    # Identical documents could cause zero singular values
    lsi.add_item 'Exactly the same text', 'A'
    lsi.add_item 'Exactly the same text', 'A'
    lsi.add_item 'Different content here', 'B'

    # Should handle gracefully without crashing
    lsi.build_index

    refute_predicate lsi, :needs_rebuild?
  end

  def test_single_word_documents
    lsi = Classifier::LSI.new auto_rebuild: false

    # Very short documents could cause edge cases
    lsi.add_item 'dog', 'Animal'
    lsi.add_item 'cat', 'Animal'
    lsi.add_item 'car', 'Vehicle'

    # Should handle gracefully
    lsi.build_index

    refute_predicate lsi, :needs_rebuild?
  end

  def test_empty_word_hash_handling
    lsi = Classifier::LSI.new auto_rebuild: false

    # Documents with only stop words result in empty word hashes
    lsi.add_item 'the a an', 'StopWords'
    lsi.add_item 'Dogs are great', 'Animal'
    lsi.add_item 'Cats are nice', 'Animal'

    # Should handle gracefully
    lsi.build_index

    refute_predicate lsi, :needs_rebuild?
  end

  def test_large_similar_document_sets
    # Regression test for issue #72
    # When many similar documents create few unique terms (M < N),
    # native Ruby SVD returns transposed dimensions causing ErrDimensionMismatch
    lsi = Classifier::LSI.new auto_rebuild: false

    10.times do |i|
      lsi.add_item "This text deals with dogs. Dogs number #{i}.", 'Dog'
    end
    10.times do |i|
      lsi.add_item "This text deals with cats. Cats number #{i}.", 'Cat'
    end

    lsi.build_index

    result = lsi.classify('Dogs are great pets')

    assert_equal 'Dog', result
  end

  # Save/Load tests

  def test_as_json
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    data = lsi.as_json

    assert_instance_of Hash, data
    assert_equal 1, data[:version]
    assert_equal 'lsi', data[:type]
    assert_equal 3, data[:items].size
    assert data[:auto_rebuild]
  end

  def test_to_json
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    json = lsi.to_json
    data = JSON.parse(json)

    assert_equal 1, data['version']
    assert_equal 'lsi', data['type']
    assert_equal 3, data['items'].size
    assert data['auto_rebuild']
  end

  def test_from_json_with_string
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    json = lsi.to_json
    loaded = Classifier::LSI.from_json(json)

    assert_equal lsi.items.sort, loaded.items.sort
    assert_equal lsi.classify(@str1), loaded.classify(@str1)
  end

  def test_from_json_with_hash
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    hash = JSON.parse(lsi.to_json)
    loaded = Classifier::LSI.from_json(hash)

    assert_equal lsi.items.sort, loaded.items.sort
    assert_equal lsi.classify(@str1), loaded.classify(@str1)
  end

  def test_from_json_invalid_type
    invalid_json = { version: 1, type: 'invalid' }.to_json

    assert_raises(ArgumentError) { Classifier::LSI.from_json(invalid_json) }
  end

  def test_save_and_load
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'lsi.json')
      lsi.save(path)

      assert_path_exists path, 'Save should create file'

      loaded = Classifier::LSI.load(path)

      assert_equal lsi.items.sort, loaded.items.sort
      assert_equal 'Dog', loaded.classify(@str1)
      assert_equal 'Cat', loaded.classify(@str3)
    end
  end

  def test_save_load_preserves_classification
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'lsi.json')
      lsi.save(path)
      loaded = Classifier::LSI.load(path)

      # Verify classifications match
      assert_equal lsi.classify(@str1), loaded.classify(@str1)
      assert_equal lsi.classify('Dogs are nice'), loaded.classify('Dogs are nice')
      assert_equal lsi.classify('Cats are cute'), loaded.classify('Cats are cute')
    end
  end

  def test_save_load_preserves_auto_rebuild_setting
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.build_index

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'lsi.json')
      lsi.save(path)
      loaded = Classifier::LSI.load(path)

      refute loaded.auto_rebuild, 'Should preserve auto_rebuild: false setting'
    end
  end

  def test_loaded_lsi_can_continue_adding_items
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'lsi.json')
      lsi.save(path)
      loaded = Classifier::LSI.load(path)

      # Continue adding items to loaded LSI
      loaded.add_item @str3, 'Cat'
      loaded.add_item @str4, 'Cat'

      assert_equal 4, loaded.items.size
      assert_equal 'Cat', loaded.classify(@str3)
    end
  end

  def test_save_load_search_functionality
    lsi = Classifier::LSI.new
    [@str1, @str2, @str3, @str4, @str5].each { |x| lsi << x }

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'lsi.json')
      lsi.save(path)
      loaded = Classifier::LSI.load(path)

      # Verify search works after load
      assert_equal lsi.search('dog', 3), loaded.search('dog', 3)
    end
  end

  # Cutoff parameter validation tests (Issue #67)

  def test_build_index_cutoff_validation_too_low
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    assert_raises(ArgumentError) { lsi.build_index(0.0) }
    assert_raises(ArgumentError) { lsi.build_index(-0.5) }
  end

  def test_build_index_cutoff_validation_too_high
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    assert_raises(ArgumentError) { lsi.build_index(1.0) }
    assert_raises(ArgumentError) { lsi.build_index(1.5) }
  end

  def test_build_index_cutoff_validation_valid_range
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    # Should not raise for valid cutoffs
    lsi.build_index(0.01)
    lsi.build_index(0.5)
    lsi.build_index(0.99)
  end

  def test_classify_cutoff_validation
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    assert_raises(ArgumentError) { lsi.classify(@str1, 0.0) }
    assert_raises(ArgumentError) { lsi.classify(@str1, 1.0) }
    assert_raises(ArgumentError) { lsi.classify(@str1, -0.1) }
    assert_raises(ArgumentError) { lsi.classify(@str1, 1.5) }
  end

  def test_vote_cutoff_validation
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    assert_raises(ArgumentError) { lsi.vote(@str1, 0.0) }
    assert_raises(ArgumentError) { lsi.vote(@str1, 1.0) }
  end

  def test_classify_with_confidence_cutoff_validation
    lsi = Classifier::LSI.new
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'

    assert_raises(ArgumentError) { lsi.classify_with_confidence(@str1, 0.0) }
    assert_raises(ArgumentError) { lsi.classify_with_confidence(@str1, 1.0) }
  end

  # Singular value introspection tests (Issue #67)

  def test_singular_values_nil_before_build
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'

    assert_nil lsi.singular_values
  end

  def test_singular_values_populated_after_build
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.build_index

    refute_nil lsi.singular_values
    assert_instance_of Array, lsi.singular_values
    assert lsi.singular_values.all? { |v| v.is_a?(Numeric) }
    assert lsi.singular_values.size.positive?
  end

  def test_singular_values_sorted_descending
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'
    lsi.build_index

    values = lsi.singular_values
    sorted = values.sort.reverse

    assert_equal sorted, values, 'Singular values should be sorted in descending order'
  end

  def test_singular_value_spectrum_nil_before_build
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'

    assert_nil lsi.singular_value_spectrum
  end

  def test_singular_value_spectrum_structure
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'
    lsi.build_index

    spectrum = lsi.singular_value_spectrum

    refute_nil spectrum
    assert_instance_of Array, spectrum

    # Each entry should have required keys
    spectrum.each_with_index do |entry, i|
      assert_equal i, entry[:dimension]
      assert entry.key?(:value)
      assert entry.key?(:percentage)
      assert entry.key?(:cumulative_percentage)
    end
  end

  def test_singular_value_spectrum_percentages
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'
    lsi.build_index

    spectrum = lsi.singular_value_spectrum

    # Individual percentages should sum to 1
    total_pct = spectrum.sum { |e| e[:percentage] }
    assert_in_delta 1.0, total_pct, 0.001

    # Cumulative should reach 1.0 at the end
    assert_in_delta 1.0, spectrum.last[:cumulative_percentage], 0.001

    # Cumulative should be monotonically increasing
    spectrum.each_cons(2) do |a, b|
      assert_operator a[:cumulative_percentage], :<=, b[:cumulative_percentage]
    end
  end

  def test_singular_value_spectrum_for_tuning
    lsi = Classifier::LSI.new auto_rebuild: false
    lsi.add_item @str1, 'Dog'
    lsi.add_item @str2, 'Dog'
    lsi.add_item @str3, 'Cat'
    lsi.add_item @str4, 'Cat'
    lsi.add_item @str5, 'Bird'
    lsi.build_index

    spectrum = lsi.singular_value_spectrum

    # Find how many dimensions capture 75% of variance (the default cutoff)
    dims_for_75 = spectrum.find_index { |e| e[:cumulative_percentage] >= 0.75 }

    # This should be usable for tuning decisions
    refute_nil dims_for_75, 'Should be able to find dimensions for 75% variance'
    assert dims_for_75 < spectrum.size, 'Some dimensions should be below 75% threshold'
  end
end
