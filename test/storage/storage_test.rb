require_relative '../test_helper'

class StorageTest < Minitest::Test
  # Storage::Base tests
  def test_base_storage_raises_not_implemented_for_write
    storage = Classifier::Storage::Base.new
    assert_raises(NotImplementedError) { storage.write('data') }
  end

  def test_base_storage_raises_not_implemented_for_read
    storage = Classifier::Storage::Base.new
    assert_raises(NotImplementedError) { storage.read }
  end

  def test_base_storage_raises_not_implemented_for_delete
    storage = Classifier::Storage::Base.new
    assert_raises(NotImplementedError) { storage.delete }
  end

  def test_base_storage_raises_not_implemented_for_exists
    storage = Classifier::Storage::Base.new
    assert_raises(NotImplementedError) { storage.exists? }
  end

  # Storage::Memory tests
  def test_memory_storage_write_and_read
    storage = Classifier::Storage::Memory.new
    storage.write('test data')

    assert_equal 'test data', storage.read
  end

  def test_memory_storage_exists_false_initially
    storage = Classifier::Storage::Memory.new

    refute_predicate storage, :exists?
  end

  def test_memory_storage_exists_true_after_write
    storage = Classifier::Storage::Memory.new
    storage.write('test data')

    assert_predicate storage, :exists?
  end

  def test_memory_storage_delete
    storage = Classifier::Storage::Memory.new
    storage.write('test data')
    storage.delete

    refute_predicate storage, :exists?
    assert_nil storage.read
  end

  def test_memory_storage_returns_nil_when_empty
    storage = Classifier::Storage::Memory.new

    assert_nil storage.read
  end

  # Storage::File tests
  def test_file_storage_write_and_read
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.json')
      storage = Classifier::Storage::File.new(path: path)
      storage.write('{"test": "data"}')

      assert_equal '{"test": "data"}', storage.read
    end
  end

  def test_file_storage_exists_false_initially
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'nonexistent.json')
      storage = Classifier::Storage::File.new(path: path)

      refute_predicate storage, :exists?
    end
  end

  def test_file_storage_exists_true_after_write
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.json')
      storage = Classifier::Storage::File.new(path: path)
      storage.write('test data')

      assert_predicate storage, :exists?
    end
  end

  def test_file_storage_delete
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.json')
      storage = Classifier::Storage::File.new(path: path)
      storage.write('test data')
      storage.delete

      refute_predicate storage, :exists?
    end
  end

  def test_file_storage_returns_nil_when_missing
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'nonexistent.json')
      storage = Classifier::Storage::File.new(path: path)

      assert_nil storage.read
    end
  end

  def test_file_storage_exposes_path
    storage = Classifier::Storage::File.new(path: '/some/path.json')

    assert_equal '/some/path.json', storage.path
  end
end

class BayesStorageTest < Minitest::Test
  def setup
    @classifier = Classifier::Bayes.new 'Spam', 'Ham'
  end

  # Dirty tracking tests
  def test_new_classifier_is_not_dirty
    refute_predicate @classifier, :dirty?
  end

  def test_training_makes_classifier_dirty
    @classifier.train_spam 'buy now'

    assert_predicate @classifier, :dirty?
  end

  def test_untraining_makes_classifier_dirty
    @classifier.train_spam 'buy now'
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.save

    refute_predicate @classifier, :dirty?

    @classifier.untrain_spam 'buy now'

    assert_predicate @classifier, :dirty?
  end

  def test_add_category_makes_classifier_dirty
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.save

    refute_predicate @classifier, :dirty?

    @classifier.add_category 'Phishing'

    assert_predicate @classifier, :dirty?
  end

  def test_remove_category_makes_classifier_dirty
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.save

    refute_predicate @classifier, :dirty?

    @classifier.remove_category 'Spam'

    assert_predicate @classifier, :dirty?
  end

  # Storage accessor tests
  def test_storage_accessor
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage

    assert_equal storage, @classifier.storage
  end

  def test_storage_is_nil_by_default
    assert_nil @classifier.storage
  end

  # Save tests
  def test_save_raises_without_storage
    assert_raises(ArgumentError) { @classifier.save }
  end

  def test_save_with_storage
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.train_spam 'buy now'
    @classifier.save

    assert_predicate storage, :exists?
  end

  def test_save_clears_dirty_flag
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.train_spam 'buy now'

    assert_predicate @classifier, :dirty?

    @classifier.save

    refute_predicate @classifier, :dirty?
  end

  def test_save_to_file_clears_dirty_flag
    @classifier.train_spam 'buy now'

    assert_predicate @classifier, :dirty?

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'classifier.json')
      @classifier.save_to_file(path)

      refute_predicate @classifier, :dirty?
    end
  end

  # Reload tests
  def test_reload_raises_without_storage
    assert_raises(ArgumentError) { @classifier.reload }
  end

  def test_reload_raises_when_dirty
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.train_spam 'buy now'
    @classifier.save

    @classifier.train_ham 'hello friend'

    assert_predicate @classifier, :dirty?

    assert_raises(Classifier::UnsavedChangesError) { @classifier.reload }
  end

  def test_reload_raises_when_no_saved_state
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    assert_raises(Classifier::StorageError) { @classifier.reload }
  end

  def test_reload_restores_saved_state
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.train_spam 'buy now limited offer'
    @classifier.save

    original_classification = @classifier.classify('buy now')

    # Modify the classifier (but don't mark as dirty for this test)
    @classifier.instance_variable_set(:@dirty, false)

    result = @classifier.reload

    assert_equal @classifier, result
    assert_equal original_classification, @classifier.classify('buy now')
  end

  def test_reload_bang_forces_reload_even_when_dirty
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.train_spam 'buy now'
    @classifier.save

    @classifier.train_ham 'hello friend'

    assert_predicate @classifier, :dirty?

    @classifier.reload!

    refute_predicate @classifier, :dirty?
  end

  def test_reload_bang_raises_when_no_saved_state
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    assert_raises(Classifier::StorageError) { @classifier.reload! }
  end

  # Load with storage tests
  def test_load_with_storage
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.train_spam 'buy now limited offer'
    @classifier.train_ham 'hello friend'
    @classifier.save

    loaded = Classifier::Bayes.load(storage: storage)

    assert_equal storage, loaded.storage
    assert_equal @classifier.classify('buy now'), loaded.classify('buy now')
    assert_equal @classifier.classify('hello friend'), loaded.classify('hello friend')
  end

  def test_load_raises_when_no_saved_state
    storage = Classifier::Storage::Memory.new
    assert_raises(Classifier::StorageError) { Classifier::Bayes.load(storage: storage) }
  end

  def test_loaded_classifier_can_save_immediately
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.train_spam 'buy now'
    @classifier.save

    loaded = Classifier::Bayes.load(storage: storage)
    loaded.train_ham 'hello friend'
    loaded.save # Should not raise

    reloaded = Classifier::Bayes.load(storage: storage)

    assert_equal 'Ham', reloaded.classify('hello friend')
  end

  # Marshal tests
  def test_marshal_preserves_dirty_flag
    @classifier.train_spam 'buy now'

    assert_predicate @classifier, :dirty?

    dumped = Marshal.dump(@classifier)
    loaded = Marshal.load(dumped)

    assert_predicate loaded, :dirty?
  end

  def test_marshal_does_not_preserve_storage
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.train_spam 'buy now'

    dumped = Marshal.dump(@classifier)
    loaded = Marshal.load(dumped)

    assert_nil loaded.storage
  end
end

class LSIStorageTest < Minitest::Test
  def setup
    @lsi = Classifier::LSI.new
    @str1 = 'Dogs love to run and play outside with their owners'
    @str2 = 'Cats prefer to relax indoors and sleep all day'
  end

  # Dirty tracking tests
  def test_new_lsi_is_not_dirty
    refute_predicate @lsi, :dirty?
  end

  def test_add_item_makes_lsi_dirty
    @lsi.add_item @str1, 'Dog'

    assert_predicate @lsi, :dirty?
  end

  def test_remove_item_makes_lsi_dirty
    @lsi.add_item @str1, 'Dog'
    storage = Classifier::Storage::Memory.new
    @lsi.storage = storage
    @lsi.save

    refute_predicate @lsi, :dirty?

    @lsi.remove_item @str1

    assert_predicate @lsi, :dirty?
  end

  # Storage accessor tests
  def test_storage_accessor
    storage = Classifier::Storage::Memory.new
    @lsi.storage = storage

    assert_equal storage, @lsi.storage
  end

  def test_storage_is_nil_by_default
    assert_nil @lsi.storage
  end

  # Save tests
  def test_save_raises_without_storage
    assert_raises(ArgumentError) { @lsi.save }
  end

  def test_save_with_storage
    storage = Classifier::Storage::Memory.new
    @lsi.storage = storage
    @lsi.add_item @str1, 'Dog'
    @lsi.add_item @str2, 'Cat'
    @lsi.save

    assert_predicate storage, :exists?
  end

  def test_save_clears_dirty_flag
    storage = Classifier::Storage::Memory.new
    @lsi.storage = storage
    @lsi.add_item @str1, 'Dog'

    assert_predicate @lsi, :dirty?

    @lsi.add_item @str2, 'Cat'
    @lsi.save

    refute_predicate @lsi, :dirty?
  end

  def test_save_to_file_clears_dirty_flag
    @lsi.add_item @str1, 'Dog'
    @lsi.add_item @str2, 'Cat'

    assert_predicate @lsi, :dirty?

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'lsi.json')
      @lsi.save_to_file(path)

      refute_predicate @lsi, :dirty?
    end
  end

  # Reload tests
  def test_reload_raises_without_storage
    assert_raises(ArgumentError) { @lsi.reload }
  end

  def test_reload_raises_when_dirty
    storage = Classifier::Storage::Memory.new
    @lsi.storage = storage
    @lsi.add_item @str1, 'Dog'
    @lsi.add_item @str2, 'Cat'
    @lsi.save

    @lsi.add_item 'Birds fly in the sky', 'Bird'

    assert_predicate @lsi, :dirty?

    assert_raises(Classifier::UnsavedChangesError) { @lsi.reload }
  end

  def test_reload_raises_when_no_saved_state
    storage = Classifier::Storage::Memory.new
    @lsi.storage = storage
    assert_raises(Classifier::StorageError) { @lsi.reload }
  end

  def test_reload_bang_forces_reload_even_when_dirty
    storage = Classifier::Storage::Memory.new
    @lsi.storage = storage
    @lsi.add_item @str1, 'Dog'
    @lsi.add_item @str2, 'Cat'
    @lsi.save

    @lsi.add_item 'Birds fly in the sky', 'Bird'

    assert_predicate @lsi, :dirty?

    @lsi.reload!

    refute_predicate @lsi, :dirty?
    assert_equal 2, @lsi.items.size
  end

  def test_reload_bang_raises_when_no_saved_state
    storage = Classifier::Storage::Memory.new
    @lsi.storage = storage
    assert_raises(Classifier::StorageError) { @lsi.reload! }
  end

  # Load with storage tests
  def test_load_with_storage
    storage = Classifier::Storage::Memory.new
    @lsi.storage = storage
    @lsi.add_item @str1, 'Dog'
    @lsi.add_item @str2, 'Cat'
    @lsi.save

    loaded = Classifier::LSI.load(storage: storage)

    assert_equal storage, loaded.storage
    assert_equal 2, loaded.items.size
  end

  def test_load_raises_when_no_saved_state
    storage = Classifier::Storage::Memory.new
    assert_raises(Classifier::StorageError) { Classifier::LSI.load(storage: storage) }
  end

  def test_loaded_lsi_can_save_immediately
    storage = Classifier::Storage::Memory.new
    @lsi.storage = storage
    @lsi.add_item @str1, 'Dog'
    @lsi.add_item @str2, 'Cat'
    @lsi.save

    loaded = Classifier::LSI.load(storage: storage)
    loaded.add_item 'Birds fly in the sky', 'Bird'
    loaded.save # Should not raise

    reloaded = Classifier::LSI.load(storage: storage)

    assert_equal 3, reloaded.items.size
  end

  # Marshal tests
  def test_marshal_preserves_dirty_flag
    @lsi.add_item @str1, 'Dog'
    @lsi.add_item @str2, 'Cat'

    assert_predicate @lsi, :dirty?

    dumped = Marshal.dump(@lsi)
    loaded = Marshal.load(dumped)

    assert_predicate loaded, :dirty?
  end

  def test_marshal_does_not_preserve_storage
    storage = Classifier::Storage::Memory.new
    @lsi.storage = storage
    @lsi.add_item @str1, 'Dog'
    @lsi.add_item @str2, 'Cat'

    dumped = Marshal.dump(@lsi)
    loaded = Marshal.load(dumped)

    assert_nil loaded.storage
  end
end
