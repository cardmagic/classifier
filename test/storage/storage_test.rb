require_relative '../test_helper'

class StorageAPIConsistencyTest < Minitest::Test
  # Dynamically discover all classifier/vectorizer classes
  CLASSIFIERS = Classifier.constants.filter_map do |const|
    klass = Classifier.const_get(const)
    next unless klass.is_a?(Class)

    klass if klass.method_defined?(:classify) || klass.method_defined?(:transform)
  end.freeze

  INSTANCE_METHODS = %i[save reload reload! dirty? storage storage=].freeze
  CLASS_METHODS = %i[load].freeze

  def test_classifiers_discovered
    assert_operator CLASSIFIERS.size, :>=, 5, "Expected at least 5 classifiers, found: #{CLASSIFIERS.map(&:name)}"
  end

  CLASSIFIERS.each do |klass|
    class_name = klass.name.split('::').last.downcase

    INSTANCE_METHODS.each do |method|
      define_method "test_#{class_name}_responds_to_#{method}" do
        assert_respond_to klass.allocate, method, "#{klass} missing ##{method}"
      end
    end

    CLASS_METHODS.each do |method|
      define_method "test_#{class_name}_class_responds_to_#{method}" do
        assert_respond_to klass, method, "#{klass} missing .#{method}"
      end
    end
  end
end

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

class LogisticRegressionStorageTest < Minitest::Test
  def setup
    @classifier = Classifier::LogisticRegression.new 'Spam', 'Ham'
  end

  # Dirty tracking tests
  def test_new_classifier_is_not_dirty
    refute_predicate @classifier, :dirty?
  end

  def test_training_makes_classifier_dirty
    @classifier.train_spam 'buy now'

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
    @classifier.train_ham 'hello friend'
    @classifier.save

    assert_predicate storage, :exists?
  end

  def test_save_clears_dirty_flag
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.train_spam 'buy now'
    @classifier.train_ham 'hello friend'

    assert_predicate @classifier, :dirty?

    @classifier.save

    refute_predicate @classifier, :dirty?
  end

  def test_save_to_file_clears_dirty_flag
    @classifier.train_spam 'buy now'
    @classifier.train_ham 'hello friend'

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
    @classifier.train_ham 'hello friend'
    @classifier.save

    @classifier.train_spam 'more spam'

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
    @classifier.train_ham 'hello friend meeting'
    @classifier.fit
    @classifier.save

    original_classification = @classifier.classify('buy now')

    @classifier.instance_variable_set(:@dirty, false)

    result = @classifier.reload

    assert_equal @classifier, result
    assert_equal original_classification, @classifier.classify('buy now')
  end

  def test_reload_bang_forces_reload_even_when_dirty
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.train_spam 'buy now'
    @classifier.train_ham 'hello friend'
    @classifier.save

    @classifier.train_spam 'more spam'

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
    @classifier.train_ham 'hello friend meeting'
    @classifier.fit
    @classifier.save

    loaded = Classifier::LogisticRegression.load(storage: storage)

    assert_equal storage, loaded.storage
    assert_equal @classifier.classify('buy now'), loaded.classify('buy now')
    assert_equal @classifier.classify('hello friend'), loaded.classify('hello friend')
  end

  def test_load_raises_when_no_saved_state
    storage = Classifier::Storage::Memory.new

    assert_raises(Classifier::StorageError) { Classifier::LogisticRegression.load(storage: storage) }
  end

  def test_loaded_classifier_can_save_immediately
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.train_spam 'buy now'
    @classifier.train_ham 'hello friend'
    @classifier.fit
    @classifier.save

    loaded = Classifier::LogisticRegression.load(storage: storage)
    loaded.train_spam 'more spam words'
    loaded.fit
    loaded.save

    reloaded = Classifier::LogisticRegression.load(storage: storage)

    assert_equal 'Spam', reloaded.classify('spam words')
  end

  # Marshal tests
  def test_marshal_preserves_fitted_state
    @classifier.train_spam 'buy now'
    @classifier.train_ham 'hello friend'
    @classifier.fit

    assert_predicate @classifier, :fitted?

    dumped = Marshal.dump(@classifier)
    loaded = Marshal.load(dumped)

    assert_predicate loaded, :fitted?
  end

  def test_marshal_does_not_preserve_storage
    storage = Classifier::Storage::Memory.new
    @classifier.storage = storage
    @classifier.train_spam 'buy now'
    @classifier.train_ham 'hello friend'

    dumped = Marshal.dump(@classifier)
    loaded = Marshal.load(dumped)

    assert_nil loaded.storage
  end
end

class TFIDFStorageTest < Minitest::Test
  def setup
    @tfidf = Classifier::TFIDF.new
    @documents = ['Dogs are great pets', 'Cats are independent', 'Birds can fly']
  end

  # Dirty tracking tests
  def test_new_tfidf_is_not_dirty
    refute_predicate @tfidf, :dirty?
  end

  def test_fit_makes_tfidf_dirty
    @tfidf.fit(@documents)

    assert_predicate @tfidf, :dirty?
  end

  # Storage accessor tests
  def test_storage_accessor
    storage = Classifier::Storage::Memory.new
    @tfidf.storage = storage

    assert_equal storage, @tfidf.storage
  end

  def test_storage_is_nil_by_default
    assert_nil @tfidf.storage
  end

  # Save tests
  def test_save_raises_without_storage
    @tfidf.fit(@documents)

    assert_raises(ArgumentError) { @tfidf.save }
  end

  def test_save_with_storage
    storage = Classifier::Storage::Memory.new
    @tfidf.storage = storage
    @tfidf.fit(@documents)
    @tfidf.save

    assert_predicate storage, :exists?
  end

  def test_save_clears_dirty_flag
    storage = Classifier::Storage::Memory.new
    @tfidf.storage = storage
    @tfidf.fit(@documents)

    assert_predicate @tfidf, :dirty?

    @tfidf.save

    refute_predicate @tfidf, :dirty?
  end

  def test_save_to_file_clears_dirty_flag
    @tfidf.fit(@documents)

    assert_predicate @tfidf, :dirty?

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'tfidf.json')
      @tfidf.save_to_file(path)

      refute_predicate @tfidf, :dirty?
    end
  end

  # Reload tests
  def test_reload_raises_without_storage
    assert_raises(ArgumentError) { @tfidf.reload }
  end

  def test_reload_raises_when_dirty
    storage = Classifier::Storage::Memory.new
    @tfidf.storage = storage
    @tfidf.fit(@documents)
    @tfidf.save

    @tfidf.fit(['New documents here'])

    assert_predicate @tfidf, :dirty?

    assert_raises(Classifier::UnsavedChangesError) { @tfidf.reload }
  end

  def test_reload_raises_when_no_saved_state
    storage = Classifier::Storage::Memory.new
    @tfidf.storage = storage

    assert_raises(Classifier::StorageError) { @tfidf.reload }
  end

  def test_reload_restores_saved_state
    storage = Classifier::Storage::Memory.new
    @tfidf.storage = storage
    @tfidf.fit(@documents)
    @tfidf.save

    original_vocab_size = @tfidf.vocabulary.size

    @tfidf.instance_variable_set(:@dirty, false)

    result = @tfidf.reload

    assert_equal @tfidf, result
    assert_equal original_vocab_size, @tfidf.vocabulary.size
  end

  def test_reload_bang_forces_reload_even_when_dirty
    storage = Classifier::Storage::Memory.new
    @tfidf.storage = storage
    @tfidf.fit(@documents)
    @tfidf.save

    original_vocab_size = @tfidf.vocabulary.size

    @tfidf.fit(['Completely different documents with new words'])

    assert_predicate @tfidf, :dirty?

    @tfidf.reload!

    refute_predicate @tfidf, :dirty?
    assert_equal original_vocab_size, @tfidf.vocabulary.size
  end

  def test_reload_bang_raises_when_no_saved_state
    storage = Classifier::Storage::Memory.new
    @tfidf.storage = storage

    assert_raises(Classifier::StorageError) { @tfidf.reload! }
  end

  # Load with storage tests
  def test_load_with_storage
    storage = Classifier::Storage::Memory.new
    @tfidf.storage = storage
    @tfidf.fit(@documents)
    @tfidf.save

    loaded = Classifier::TFIDF.load(storage: storage)

    assert_equal storage, loaded.storage
    assert_equal @tfidf.vocabulary, loaded.vocabulary
    assert_equal @tfidf.idf, loaded.idf
  end

  def test_load_raises_when_no_saved_state
    storage = Classifier::Storage::Memory.new

    assert_raises(Classifier::StorageError) { Classifier::TFIDF.load(storage: storage) }
  end

  def test_loaded_tfidf_can_save_immediately
    storage = Classifier::Storage::Memory.new
    @tfidf.storage = storage
    @tfidf.fit(@documents)
    @tfidf.save

    loaded = Classifier::TFIDF.load(storage: storage)
    loaded.fit(['New set of documents'])
    loaded.save

    reloaded = Classifier::TFIDF.load(storage: storage)

    assert_predicate reloaded, :fitted?
  end

  def test_load_from_file
    @tfidf.fit(@documents)

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'tfidf.json')
      @tfidf.save_to_file(path)

      loaded = Classifier::TFIDF.load_from_file(path)

      assert_equal @tfidf.vocabulary, loaded.vocabulary
      assert_equal @tfidf.idf, loaded.idf
    end
  end

  # Marshal tests
  def test_marshal_preserves_fitted_state
    @tfidf.fit(@documents)

    assert_predicate @tfidf, :fitted?

    dumped = Marshal.dump(@tfidf)
    loaded = Marshal.load(dumped)

    assert_predicate loaded, :fitted?
    assert_equal @tfidf.vocabulary, loaded.vocabulary
  end

  def test_marshal_does_not_preserve_storage
    storage = Classifier::Storage::Memory.new
    @tfidf.storage = storage
    @tfidf.fit(@documents)

    dumped = Marshal.dump(@tfidf)
    loaded = Marshal.load(dumped)

    assert_nil loaded.storage
  end

  def test_marshal_sets_dirty_to_false
    @tfidf.fit(@documents)

    assert_predicate @tfidf, :dirty?

    dumped = Marshal.dump(@tfidf)
    loaded = Marshal.load(dumped)

    refute_predicate loaded, :dirty?
  end
end
