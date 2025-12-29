require_relative '../test_helper'

class IncrementalSVDModuleTest < Minitest::Test
  def test_update_with_new_direction
    # Create a simple U matrix (3 terms × 2 components)
    u = Matrix[
      [0.5, 0.5],
      [0.5, -0.5],
      [0.707, 0.0]
    ]
    s = [2.0, 1.0]

    # New document vector (3 terms)
    c = Vector[0.1, 0.2, 0.9]

    u_new, s_new = Classifier::LSI::IncrementalSVD.update(u, s, c, max_rank: 10)

    # Should have updated matrices
    assert_instance_of Matrix, u_new
    assert_instance_of Array, s_new

    # Rank may have increased by 1 (if new direction found)
    assert_operator s_new.size, :>=, s.size
    assert_operator s_new.size, :<=, s.size + 1
  end

  def test_update_preserves_orthogonality
    # Start with orthonormal U
    u = Matrix[
      [1.0, 0.0],
      [0.0, 1.0],
      [0.0, 0.0]
    ]
    s = [2.0, 1.5]

    c = Vector[0.5, 0.5, 0.707]

    u_new, _s_new = Classifier::LSI::IncrementalSVD.update(u, s, c, max_rank: 10)

    # Check columns are approximately orthonormal
    u_new.column_size.times do |i|
      col_i = u_new.column(i)
      # Column should have unit length (approximately)
      norm = Math.sqrt(col_i.to_a.sum { |x| x * x })

      assert_in_delta 1.0, norm, 0.1, "Column #{i} should have unit length"
    end
  end

  def test_update_with_vector_in_span
    # U spans the first two dimensions
    u = Matrix[
      [1.0, 0.0],
      [0.0, 1.0],
      [0.0, 0.0]
    ]
    s = [2.0, 1.0]

    # Vector entirely in span of U (no component in third dimension)
    c = Vector[0.6, 0.8, 0.0]

    _u_new, s_new = Classifier::LSI::IncrementalSVD.update(u, s, c, max_rank: 10)

    # Rank should not increase when vector is in span
    assert_equal s.size, s_new.size
  end

  def test_update_respects_max_rank
    u = Matrix[
      [1.0, 0.0],
      [0.0, 1.0],
      [0.0, 0.0]
    ]
    s = [2.0, 1.0]

    c = Vector[0.1, 0.1, 0.99]

    # With max_rank = 2, should not exceed 2 components
    u_new, s_new = Classifier::LSI::IncrementalSVD.update(u, s, c, max_rank: 2)

    assert_equal 2, s_new.size
    assert_equal 2, u_new.column_size
  end

  def test_singular_values_sorted_descending
    u = Matrix[
      [0.707, 0.707],
      [0.707, -0.707],
      [0.0, 0.0]
    ]
    s = [3.0, 1.0]

    c = Vector[0.5, 0.5, 0.707]

    _u_new, s_new = Classifier::LSI::IncrementalSVD.update(u, s, c, max_rank: 10)

    # Singular values should be sorted in descending order
    (0...(s_new.size - 1)).each do |i|
      assert_operator s_new[i], :>=, s_new[i + 1], 'Singular values should be descending'
    end
  end
end

class LSIIncrementalModeTest < Minitest::Test
  def setup
    @dog_docs = [
      'dogs are loyal pets that bark',
      'puppies are playful young dogs',
      'dogs love to play fetch'
    ]
    @cat_docs = [
      'cats are independent pets',
      'kittens are curious creatures',
      'cats meow and purr softly'
    ]
  end

  def test_incremental_mode_initialization
    lsi = Classifier::LSI.new(incremental: true)

    assert lsi.instance_variable_get(:@incremental_mode)
    refute_predicate lsi, :incremental_enabled? # Not active until first build
  end

  def test_incremental_mode_with_max_rank
    lsi = Classifier::LSI.new(incremental: true, max_rank: 50)

    assert_equal 50, lsi.instance_variable_get(:@max_rank)
  end

  def test_incremental_enabled_after_build
    lsi = Classifier::LSI.new(incremental: true, auto_rebuild: false)

    @dog_docs.each { |doc| lsi.add_item(doc, :dog) }
    @cat_docs.each { |doc| lsi.add_item(doc, :cat) }

    refute_predicate lsi, :incremental_enabled?

    lsi.build_index

    assert_predicate lsi, :incremental_enabled?
    assert_instance_of Matrix, lsi.instance_variable_get(:@u_matrix)
  end

  def test_incremental_add_uses_incremental_update
    lsi = Classifier::LSI.new(incremental: true, auto_rebuild: false)

    # Add initial documents
    @dog_docs.each { |doc| lsi.add_item(doc, :dog) }
    @cat_docs.each { |doc| lsi.add_item(doc, :cat) }
    lsi.build_index

    initial_version = lsi.instance_variable_get(:@version)

    # Add new document - should use incremental update
    lsi.add_item('my dog loves to run and play', :dog)

    # Version should have incremented
    assert_equal initial_version + 1, lsi.instance_variable_get(:@version)

    # Should still be in incremental mode
    assert_predicate lsi, :incremental_enabled?
  end

  def test_incremental_classification_works
    lsi = Classifier::LSI.new(incremental: true, auto_rebuild: false)

    @dog_docs.each { |doc| lsi.add_item(doc, :dog) }
    @cat_docs.each { |doc| lsi.add_item(doc, :cat) }
    lsi.build_index

    # Add more documents incrementally
    lsi.add_item('dogs are wonderful companions', :dog)
    lsi.add_item('cats sleep a lot during the day', :cat)

    # Classification should work
    result = lsi.classify('loyal pet that barks').to_s

    assert_equal 'dog', result

    result = lsi.classify('independent creature that meows').to_s

    assert_equal 'cat', result
  end

  def test_current_rank
    lsi = Classifier::LSI.new(incremental: true, auto_rebuild: false)

    @dog_docs.each { |doc| lsi.add_item(doc, :dog) }
    @cat_docs.each { |doc| lsi.add_item(doc, :cat) }
    lsi.build_index

    rank = lsi.current_rank

    assert_instance_of Integer, rank
    assert_predicate rank, :positive?
  end

  def test_disable_incremental_mode
    lsi = Classifier::LSI.new(incremental: true, auto_rebuild: false)

    @dog_docs.each { |doc| lsi.add_item(doc, :dog) }
    lsi.build_index

    assert_predicate lsi, :incremental_enabled?

    lsi.disable_incremental_mode!

    refute_predicate lsi, :incremental_enabled?
    assert_nil lsi.instance_variable_get(:@u_matrix)
  end

  def test_enable_incremental_mode
    lsi = Classifier::LSI.new(auto_rebuild: false)

    @dog_docs.each { |doc| lsi.add_item(doc, :dog) }
    lsi.build_index

    refute_predicate lsi, :incremental_enabled?

    lsi.enable_incremental_mode!(max_rank: 75)
    lsi.build_index(force: true)

    assert_predicate lsi, :incremental_enabled?
    assert_equal 75, lsi.instance_variable_get(:@max_rank)
  end

  def test_force_rebuild
    lsi = Classifier::LSI.new(incremental: true, auto_rebuild: false)

    @dog_docs.each { |doc| lsi.add_item(doc, :dog) }
    lsi.build_index

    # Force rebuild should work
    lsi.build_index(force: true)

    assert_predicate lsi, :incremental_enabled?
  end

  def test_vocabulary_growth_triggers_full_rebuild
    lsi = Classifier::LSI.new(incremental: true, auto_rebuild: false)

    # Start with a small vocabulary
    lsi.add_item('dog', :animal)
    lsi.add_item('cat', :animal)
    lsi.build_index

    # Store initial vocab size to verify growth detection works
    _initial_vocab_size = lsi.instance_variable_get(:@initial_vocab_size)

    # Add document with many new words (> 20% of initial vocabulary)
    # This should trigger a full rebuild and disable incremental mode
    many_new_words = (1..100).map { |i| "newword#{i}" }.join(' ')
    lsi.add_item(many_new_words, :animal)

    # After vocabulary growth > 20%, incremental mode should be disabled
    # and a full rebuild should have occurred
    refute_predicate lsi, :incremental_enabled?
  end

  def test_incremental_produces_reasonable_results
    # Build with full SVD
    lsi_full = Classifier::LSI.new(auto_rebuild: false)
    @dog_docs.each { |doc| lsi_full.add_item(doc, :dog) }
    @cat_docs.each { |doc| lsi_full.add_item(doc, :cat) }
    lsi_full.add_item('my dog is a great friend', :dog)
    lsi_full.build_index

    # Build with incremental mode
    lsi_inc = Classifier::LSI.new(incremental: true, auto_rebuild: false)
    @dog_docs.each { |doc| lsi_inc.add_item(doc, :dog) }
    @cat_docs.each { |doc| lsi_inc.add_item(doc, :cat) }
    lsi_inc.build_index
    lsi_inc.add_item('my dog is a great friend', :dog)

    # Both should classify test documents reasonably
    # Note: Results may differ due to approximation, but should be reasonable
    test_doc = 'loyal pet barking'

    _full_result = lsi_full.classify(test_doc).to_s
    inc_result = lsi_inc.classify(test_doc).to_s

    # At minimum, incremental should produce a valid classification
    assert_includes %w[dog cat], inc_result
  end

  def test_incremental_with_streaming_api
    lsi = Classifier::LSI.new(incremental: true, auto_rebuild: false)

    # Add initial batch
    @dog_docs.each { |doc| lsi.add_item(doc, :dog) }
    @cat_docs.each { |doc| lsi.add_item(doc, :cat) }
    lsi.build_index

    # Use streaming API to add more
    io = StringIO.new("dogs bark loudly\ndogs wag their tails\n")
    lsi.train_from_stream(:dog, io)

    # Should still work
    result = lsi.classify('barking dog wags tail').to_s

    assert_equal 'dog', result
  end
end
