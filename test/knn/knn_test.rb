require_relative '../test_helper'

class KNNTest < Minitest::Test
  def setup
    @str1 = 'This text deals with dogs. Dogs.'
    @str2 = 'This text involves dogs too. Dogs!'
    @str3 = 'This text revolves around cats. Cats.'
    @str4 = 'This text also involves cats. Cats!'
    @str5 = 'This text involves birds. Birds.'
  end

  # Initialization tests

  def test_default_initialization
    knn = Classifier::KNN.new

    assert_equal 5, knn.k
    refute knn.weighted
    assert_empty knn.items
  end

  def test_custom_k_initialization
    knn = Classifier::KNN.new(k: 3)

    assert_equal 3, knn.k
  end

  def test_weighted_initialization
    knn = Classifier::KNN.new(weighted: true)

    assert knn.weighted
  end

  def test_invalid_k_raises_error
    assert_raises(ArgumentError) { Classifier::KNN.new(k: 0) }
    assert_raises(ArgumentError) { Classifier::KNN.new(k: -1) }
    assert_raises(ArgumentError) { Classifier::KNN.new(k: 1.5) }
  end

  def test_k_setter
    knn = Classifier::KNN.new(k: 5)
    knn.k = 3

    assert_equal 3, knn.k
  end

  def test_k_setter_validation
    knn = Classifier::KNN.new

    assert_raises(ArgumentError) { knn.k = 0 }
    assert_raises(ArgumentError) { knn.k = -1 }
  end

  # Adding items tests

  def test_add_with_hash_syntax
    knn = Classifier::KNN.new
    knn.add('Dog' => 'Dogs are loyal pets')
    knn.add('Cat' => 'Cats are independent')

    assert_equal 2, knn.items.size
    assert_includes knn.items, 'Dogs are loyal pets'
    assert_includes knn.items, 'Cats are independent'
  end

  def test_add_with_symbol_keys
    knn = Classifier::KNN.new
    knn.add(Dog: 'Dogs are loyal', Cat: 'Cats are independent')

    assert_equal 2, knn.items.size
    assert_equal ['Dog'], knn.categories_for('Dogs are loyal')
    assert_equal ['Cat'], knn.categories_for('Cats are independent')
  end

  def test_add_multiple_items_same_category
    knn = Classifier::KNN.new
    knn.add('Dog' => ['Dogs are loyal', 'Puppies are cute', 'Canines are friendly'])

    assert_equal 3, knn.items.size
    assert_equal ['Dog'], knn.categories_for('Dogs are loyal')
    assert_equal ['Dog'], knn.categories_for('Puppies are cute')
    assert_equal ['Dog'], knn.categories_for('Canines are friendly')
  end

  def test_add_batch_operations
    knn = Classifier::KNN.new
    knn.add(
      'Dog' => ['Dogs are loyal', 'Puppies are cute'],
      'Cat' => ['Cats are independent', 'Kittens are playful']
    )

    assert_equal 4, knn.items.size
    assert_equal ['Dog'], knn.categories_for('Dogs are loyal')
    assert_equal ['Cat'], knn.categories_for('Cats are independent')
  end

  # Classification tests

  def test_basic_classification
    knn = Classifier::KNN.new(k: 3)
    knn.add(
      'Dog' => [@str1, @str2],
      'Cat' => [@str3, @str4],
      'Bird' => @str5
    )

    assert_equal 'Dog', knn.classify('This is about dogs')
    assert_equal 'Cat', knn.classify('This is about cats')
    assert_equal 'Bird', knn.classify('This is about birds')
  end

  def test_classify_empty_classifier
    knn = Classifier::KNN.new

    assert_nil knn.classify('Some text')
  end

  def test_classify_with_k_larger_than_items
    knn = Classifier::KNN.new(k: 10)
    knn.add('Dog' => 'Dogs are pets')
    knn.add('Cat' => 'Cats are pets')

    # Should still work with fewer items than k
    result = knn.classify('Dogs are great')

    refute_nil result
  end

  # classify_with_neighbors tests

  def test_classify_with_neighbors_structure
    knn = Classifier::KNN.new(k: 3)
    knn.add(
      'Dog' => [@str1, @str2],
      'Cat' => [@str3, @str4]
    )

    result = knn.classify_with_neighbors('Dogs are great pets')

    assert_instance_of Hash, result
    assert result.key?(:category)
    assert result.key?(:neighbors)
    assert result.key?(:votes)
    assert result.key?(:confidence)
  end

  def test_classify_with_neighbors_returns_neighbors
    knn = Classifier::KNN.new(k: 2)
    knn.add(
      'Dog' => [@str1, @str2],
      'Cat' => @str3
    )

    result = knn.classify_with_neighbors('Dogs are great')

    assert_equal 2, result[:neighbors].size
    result[:neighbors].each do |neighbor|
      assert neighbor.key?(:item)
      assert neighbor.key?(:category)
      assert neighbor.key?(:similarity)
    end
  end

  def test_classify_with_neighbors_empty_classifier
    knn = Classifier::KNN.new

    result = knn.classify_with_neighbors('Some text')

    assert_nil result[:category]
    assert_empty result[:neighbors]
    assert_empty result[:votes]
    assert_in_delta(0.0, result[:confidence])
  end

  def test_classify_with_neighbors_confidence
    knn = Classifier::KNN.new(k: 3)
    knn.add(
      'Dog' => [@str1, @str2],
      'Cat' => @str3
    )

    result = knn.classify_with_neighbors('Dogs are wonderful')

    assert_kind_of Float, result[:confidence]
    assert_operator result[:confidence], :>=, 0.0
    assert_operator result[:confidence], :<=, 1.0
  end

  # Weighted voting tests

  def test_weighted_voting
    knn = Classifier::KNN.new(k: 3, weighted: true)
    knn.add(
      'Dog' => [@str1, @str2],
      'Cat' => [@str3, @str4]
    )

    result = knn.classify_with_neighbors('Dogs are great')

    # Votes should be weighted by similarity
    assert knn.weighted
    # Weighted votes should have non-integer values
    assert(result[:votes].values.any? { |v| v != v.to_i })
  end

  def test_unweighted_voting
    knn = Classifier::KNN.new(k: 3, weighted: false)
    knn.add(
      'Dog' => [@str1, @str2],
      'Cat' => @str3
    )

    result = knn.classify_with_neighbors('Dogs are great')

    # Unweighted votes should be integers (counts)
    result[:votes].each_value do |vote|
      assert_equal vote.to_i.to_f, vote
    end
  end

  # Categories tests

  def test_categories
    knn = Classifier::KNN.new
    knn.add(
      'Dog' => 'Dogs are loyal',
      'Cat' => 'Cats are independent',
      'Bird' => 'Birds can fly'
    )

    cats = knn.categories

    assert_equal 3, cats.size
    assert_includes cats, 'Dog'
    assert_includes cats, 'Cat'
    assert_includes cats, 'Bird'
  end

  def test_categories_empty
    knn = Classifier::KNN.new

    assert_empty knn.categories
  end

  # Remove item tests

  def test_remove_item
    knn = Classifier::KNN.new
    knn.add('Dog' => [@str1, @str2])

    assert_equal 2, knn.items.size

    knn.remove_item(@str1)

    assert_equal 1, knn.items.size
    refute_includes knn.items, @str1
  end

  def test_remove_nonexistent_item
    knn = Classifier::KNN.new
    knn.add('Dog' => @str1)

    knn.remove_item('nonexistent')

    assert_equal 1, knn.items.size
  end

  # Serialization tests

  def test_as_json
    knn = Classifier::KNN.new(k: 3, weighted: true)
    knn.add('Dog' => @str1, 'Cat' => @str2)

    data = knn.as_json

    assert_instance_of Hash, data
    assert_equal 1, data[:version]
    assert_equal 'knn', data[:type]
    assert_equal 3, data[:k]
    assert data[:weighted]
    assert data.key?(:lsi)
  end

  def test_to_json
    knn = Classifier::KNN.new(k: 3)
    knn.add('Dog' => @str1)

    json = knn.to_json
    data = JSON.parse(json)

    assert_equal 'knn', data['type']
    assert_equal 3, data['k']
  end

  def test_from_json_with_string
    knn = Classifier::KNN.new(k: 3, weighted: true)
    knn.add(
      'Dog' => [@str1, @str2],
      'Cat' => @str3
    )

    json = knn.to_json
    loaded = Classifier::KNN.from_json(json)

    assert_equal knn.k, loaded.k
    assert_equal knn.weighted, loaded.weighted
    assert_equal knn.items.sort, loaded.items.sort
    assert_equal knn.classify('Dogs are great'), loaded.classify('Dogs are great')
  end

  def test_from_json_with_hash
    knn = Classifier::KNN.new(k: 5)
    knn.add('Dog' => @str1, 'Cat' => @str2)

    hash = JSON.parse(knn.to_json)
    loaded = Classifier::KNN.from_json(hash)

    assert_equal knn.k, loaded.k
    assert_equal knn.items.sort, loaded.items.sort
  end

  def test_from_json_invalid_type
    invalid_json = { version: 1, type: 'invalid' }.to_json

    assert_raises(ArgumentError) { Classifier::KNN.from_json(invalid_json) }
  end

  def test_save_and_load_from_file
    knn = Classifier::KNN.new(k: 3, weighted: true)
    knn.add(
      'Dog' => [@str1, @str2],
      'Cat' => [@str3, @str4]
    )

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'knn.json')
      knn.save_to_file(path)

      assert_path_exists path

      loaded = Classifier::KNN.load_from_file(path)

      assert_equal knn.k, loaded.k
      assert_equal knn.weighted, loaded.weighted
      assert_equal knn.classify('Dogs are great'), loaded.classify('Dogs are great')
    end
  end

  def test_save_load_preserves_classification
    knn = Classifier::KNN.new(k: 3)
    knn.add(
      'Dog' => [@str1, @str2],
      'Cat' => [@str3, @str4],
      'Bird' => @str5
    )

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'knn.json')
      knn.save_to_file(path)
      loaded = Classifier::KNN.load_from_file(path)

      assert_equal knn.classify(@str1), loaded.classify(@str1)
      assert_equal knn.classify('Dogs are nice'), loaded.classify('Dogs are nice')
      assert_equal knn.classify('Cats are cute'), loaded.classify('Cats are cute')
    end
  end

  # Marshal tests

  def test_marshal_dump_load
    knn = Classifier::KNN.new(k: 3, weighted: true)
    knn.add('Dog' => [@str1, @str2], 'Cat' => @str3)

    dumped = Marshal.dump(knn)
    loaded = Marshal.load(dumped)

    assert_equal knn.k, loaded.k
    assert_equal knn.weighted, loaded.weighted
    assert_equal knn.items.sort, loaded.items.sort
    assert_equal knn.classify('Dogs are great'), loaded.classify('Dogs are great')
  end

  # Dirty tracking tests

  def test_dirty_after_add
    knn = Classifier::KNN.new

    refute_predicate knn, :dirty?

    knn.add('Dog' => 'Dogs are great')

    assert_predicate knn, :dirty?
  end

  def test_dirty_after_remove
    knn = Classifier::KNN.new
    knn.add('Dog' => 'Dogs are great')
    knn.instance_variable_set(:@dirty, false)

    knn.remove_item('Dogs are great')

    assert_predicate knn, :dirty?
  end

  def test_save_clears_dirty
    knn = Classifier::KNN.new
    knn.add('Dog' => 'Dogs are great')

    assert_predicate knn, :dirty?

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'knn.json')
      knn.save_to_file(path)

      refute_predicate knn, :dirty?
    end
  end

  # Storage tests

  def test_save_without_storage_raises
    knn = Classifier::KNN.new

    assert_raises(ArgumentError) { knn.save }
  end

  def test_reload_without_storage_raises
    knn = Classifier::KNN.new

    assert_raises(ArgumentError) { knn.reload }
  end

  def test_storage_save_and_load
    knn = Classifier::KNN.new(k: 3)
    knn.add('Dog' => @str1, 'Cat' => @str2)

    storage = Classifier::Storage::Memory.new
    knn.storage = storage
    knn.save

    loaded = Classifier::KNN.load(storage: storage)

    assert_equal knn.k, loaded.k
    assert_equal knn.items.sort, loaded.items.sort
  end

  def test_reload
    storage = Classifier::Storage::Memory.new

    knn = Classifier::KNN.new(k: 3)
    knn.add('Dog' => @str1)
    knn.storage = storage
    knn.save

    # Modify after save
    knn.add('Cat' => @str2)

    assert_equal 2, knn.items.size

    # Reload should restore to saved state
    knn.reload!

    assert_equal 1, knn.items.size
    assert_includes knn.items, @str1
  end

  def test_reload_with_unsaved_changes
    storage = Classifier::Storage::Memory.new

    knn = Classifier::KNN.new
    knn.add('Dog' => @str1)
    knn.storage = storage
    knn.save

    knn.add('Cat' => @str2)

    assert_raises(Classifier::UnsavedChangesError) { knn.reload }
  end

  def test_reload_success
    storage = Classifier::Storage::Memory.new

    knn = Classifier::KNN.new(k: 3)
    knn.add('Dog' => @str1)
    knn.storage = storage
    knn.save

    # Modify but don't mark as dirty (simulate external change)
    knn.instance_variable_set(:@dirty, false)

    result = knn.reload

    assert_same knn, result
    refute_predicate knn, :dirty?
  end

  # Edge cases

  def test_single_item_classification
    knn = Classifier::KNN.new(k: 5)
    knn.add('Dog' => 'Dogs are great')

    result = knn.classify('Something about dogs')

    assert_equal 'Dog', result
  end

  def test_classification_with_very_different_text
    knn = Classifier::KNN.new(k: 3)
    knn.add(
      'Dog' => [@str1, @str2],
      'Cat' => [@str3, @str4]
    )

    # Even very different text should return some classification
    result = knn.classify('Completely unrelated computer programming text')

    refute_nil result
  end

  def test_items_returns_copy
    knn = Classifier::KNN.new
    knn.add('Dog' => 'Dogs are great')

    items = knn.items

    # Modifying returned array shouldn't affect internal state
    items.clear

    assert_equal 1, knn.items.size
  end

  # API consistency tests (with Bayes and LogisticRegression)

  def test_train_alias_for_add
    knn = Classifier::KNN.new(k: 3)
    knn.train(Dog: [@str1, @str2], Cat: [@str3, @str4])

    assert_equal 4, knn.items.size
    assert_equal 'Dog', knn.classify('This is about dogs')
    assert_equal 'Cat', knn.classify('This is about cats')
  end

  def test_dynamic_train_methods
    knn = Classifier::KNN.new(k: 3)
    knn.train_dog @str1, @str2
    knn.train_cat @str3, @str4

    assert_equal 4, knn.items.size
    # Dynamic methods create lowercase category names from method name
    assert_equal 'dog', knn.classify('This is about dogs')
    assert_equal 'cat', knn.classify('This is about cats')
  end

  def test_respond_to_train_methods
    knn = Classifier::KNN.new

    assert_respond_to knn, :train
    assert_respond_to knn, :train_spam
    assert_respond_to knn, :train_any_category
  end

  def test_classify_returns_string_not_symbol
    knn = Classifier::KNN.new(k: 3)
    knn.add(dog: [@str1, @str2], cat: [@str3, @str4])  # symbol keys

    result = knn.classify('This is about dogs')

    assert_instance_of String, result
    assert_equal 'dog', result
  end

  def test_categories_returns_array_of_strings
    knn = Classifier::KNN.new
    knn.add(dog: 'Dogs are great', cat: 'Cats are independent')

    cats = knn.categories

    assert_instance_of Array, cats
    cats.each { |cat| assert_instance_of String, cat }
    assert_includes cats, 'dog'
    assert_includes cats, 'cat'
  end
end
