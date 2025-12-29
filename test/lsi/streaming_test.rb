require_relative '../test_helper'
require 'stringio'
require 'tempfile'

class LSIStreamingTest < Minitest::Test
  def setup
    @lsi = Classifier::LSI.new
  end

  # train_from_stream tests

  def test_train_from_stream_basic
    dog_docs = "dogs are loyal pets\npuppies are playful\ndogs bark at strangers\n"
    cat_docs = "cats are independent\nkittens are curious\ncats meow softly\n"

    @lsi.train_from_stream(:dog, StringIO.new(dog_docs))
    @lsi.train_from_stream(:cat, StringIO.new(cat_docs))

    # Should be able to classify
    # Note: classify returns the category as originally stored (symbol in this case)
    result = @lsi.classify('loyal pet that barks')

    assert_equal 'dog', result.to_s
  end

  def test_train_from_stream_empty_io
    @lsi.train_from_stream(:category, StringIO.new(''))

    # No items added
    assert_empty @lsi.items
  end

  def test_train_from_stream_single_line
    @lsi.train_from_stream(:dog, StringIO.new("dogs are loyal pets\n"))
    @lsi.train_from_stream(:cat, StringIO.new("cats are independent\n"))

    # Should have 2 items
    assert_equal 2, @lsi.items.size
  end

  def test_train_from_stream_with_batch_size
    lines = (1..50).map { |i| "document number #{i} about dogs" }
    io = StringIO.new(lines.join("\n"))

    batches_processed = 0
    @lsi.train_from_stream(:dog, io, batch_size: 10) do |progress|
      batches_processed = progress.current_batch
    end

    assert_equal 5, batches_processed
  end

  def test_train_from_stream_progress_tracking
    lines = (1..25).map { |i| "document #{i}" }
    io = StringIO.new(lines.join("\n"))

    completed_values = []
    @lsi.train_from_stream(:category, io, batch_size: 10) do |progress|
      completed_values << progress.completed
    end

    assert_equal [10, 20, 25], completed_values
  end

  def test_train_from_stream_marks_dirty
    refute_predicate @lsi, :dirty?
    @lsi.train_from_stream(:category, StringIO.new("content\n"))

    assert_predicate @lsi, :dirty?
  end

  def test_train_from_stream_rebuilds_index_when_auto_rebuild
    @lsi = Classifier::LSI.new(auto_rebuild: true)

    dog_docs = "dogs are loyal\ndogs bark\n"
    cat_docs = "cats are independent\ncats meow\n"

    @lsi.train_from_stream(:dog, StringIO.new(dog_docs))
    @lsi.train_from_stream(:cat, StringIO.new(cat_docs))

    # Index should be built
    refute_predicate @lsi, :needs_rebuild?
  end

  def test_train_from_stream_skips_rebuild_when_auto_rebuild_false
    @lsi = Classifier::LSI.new(auto_rebuild: false)

    @lsi.train_from_stream(:category, StringIO.new("document one\ndocument two\n"))

    # Index should need rebuild
    assert_predicate @lsi, :needs_rebuild?
  end

  def test_train_from_stream_with_file
    Tempfile.create(['corpus', '.txt']) do |file|
      file.puts 'dogs are loyal pets'
      file.puts 'puppies are playful animals'
      file.puts 'dogs bark and play'
      file.flush
      file.rewind

      @lsi.train_from_stream(:dog, file)
    end

    @lsi.add_item('cats are independent', :cat)
    @lsi.add_item('kittens are curious', :cat)

    result = @lsi.classify('loyal pet')

    assert_equal 'dog', result.to_s
  end

  # add_batch tests

  def test_add_batch_basic
    dog_docs = ['dogs are loyal', 'puppies play', 'dogs bark']
    cat_docs = ['cats are independent', 'kittens curious', 'cats meow']

    @lsi.add_batch(dog: dog_docs, cat: cat_docs)

    assert_equal 6, @lsi.items.size
    assert_equal 'dog', @lsi.classify('loyal dog barks').to_s
  end

  def test_add_batch_with_progress
    docs = (1..30).map { |i| "document #{i}" }

    completed_values = []
    @lsi.add_batch(batch_size: 10, category: docs) do |progress|
      completed_values << progress.completed
    end

    assert_equal [10, 20, 30], completed_values
  end

  def test_add_batch_empty
    @lsi.add_batch(category: [])

    assert_empty @lsi.items
  end

  def test_add_batch_marks_dirty
    refute_predicate @lsi, :dirty?
    @lsi.add_batch(category: ['doc'])

    assert_predicate @lsi, :dirty?
  end

  def test_add_batch_rebuilds_when_auto_rebuild
    @lsi = Classifier::LSI.new(auto_rebuild: true)

    @lsi.add_batch(
      dog: ['dogs bark', 'puppies play'],
      cat: ['cats meow', 'kittens purr']
    )

    refute_predicate @lsi, :needs_rebuild?
  end

  # train_batch tests (alias for add_batch)

  def test_train_batch_positional_style
    docs = ['dogs are loyal', 'puppies play']
    @lsi.train_batch(:dog, docs)

    @lsi.add_item('cats are independent', :cat)

    assert_equal 3, @lsi.items.size
  end

  def test_train_batch_keyword_style
    @lsi.train_batch(
      dog: ['dogs are loyal', 'puppies play'],
      cat: ['cats are independent', 'kittens curious']
    )

    assert_equal 4, @lsi.items.size
    assert_equal 'dog', @lsi.classify('loyal dog').to_s
  end

  def test_train_batch_with_progress
    docs = (1..20).map { |i| "doc #{i}" }

    batches = 0
    @lsi.train_batch(:category, docs, batch_size: 5) do |_progress|
      batches += 1
    end

    assert_equal 4, batches
  end

  # Equivalence tests

  def test_train_from_stream_equivalent_to_add_item
    lsi1 = Classifier::LSI.new
    lsi2 = Classifier::LSI.new

    documents = ['dogs are loyal pets', 'puppies are playful', 'dogs bark at strangers']

    # Add with add_item
    documents.each { |doc| lsi1.add_item(doc, :dog) }

    # Add with train_from_stream
    io = StringIO.new(documents.join("\n"))
    lsi2.train_from_stream(:dog, io)

    # Both should have same items
    assert_equal lsi1.items.size, lsi2.items.size

    # Add some cat documents to both for classification
    lsi1.add_item('cats are independent', :cat)
    lsi2.add_item('cats are independent', :cat)

    # Both should classify the same
    test_doc = 'loyal playful pet'

    assert_equal lsi1.classify(test_doc).to_s, lsi2.classify(test_doc).to_s
  end

  def test_add_batch_equivalent_to_add
    lsi1 = Classifier::LSI.new
    lsi2 = Classifier::LSI.new

    dog_docs = ['dogs bark', 'puppies play']
    cat_docs = ['cats meow', 'kittens purr']

    # Add with hash-style add
    lsi1.add(dog: dog_docs, cat: cat_docs)

    # Add with add_batch
    lsi2.add_batch(dog: dog_docs, cat: cat_docs)

    # Both should have same items
    assert_equal lsi1.items.size, lsi2.items.size

    # Both should classify the same
    test_doc = 'barking dog'

    assert_equal lsi1.classify(test_doc).to_s, lsi2.classify(test_doc).to_s
  end

  # Checkpoint tests

  def test_save_checkpoint
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'lsi.json')
      @lsi.storage = Classifier::Storage::File.new(path: path)

      @lsi.add_item('dogs are loyal', :dog)
      @lsi.add_item('cats are independent', :cat)
      @lsi.save_checkpoint('50pct')

      checkpoint_path = File.join(dir, 'lsi_checkpoint_50pct.json')

      assert_path_exists checkpoint_path
    end
  end

  def test_load_checkpoint
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'lsi.json')
      storage = Classifier::Storage::File.new(path: path)
      @lsi.storage = storage

      @lsi.add_item('dogs are loyal', :dog)
      @lsi.add_item('cats are independent', :cat)
      @lsi.save_checkpoint('halfway')

      # Load from checkpoint
      loaded = Classifier::LSI.load_checkpoint(storage: storage, checkpoint_id: 'halfway')

      # Should have the same items and same classification
      assert_equal @lsi.items.size, loaded.items.size
      # Compare as strings since loaded classifier may have string categories
      assert_equal @lsi.classify('loyal dog').to_s, loaded.classify('loyal dog').to_s
    end
  end

  def test_list_checkpoints
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'lsi.json')
      @lsi.storage = Classifier::Storage::File.new(path: path)

      @lsi.add_item('content', :category)
      @lsi.save_checkpoint('10pct')
      @lsi.save_checkpoint('50pct')
      @lsi.save_checkpoint('90pct')

      checkpoints = @lsi.list_checkpoints

      assert_equal %w[10pct 50pct 90pct], checkpoints.sort
    end
  end

  def test_delete_checkpoint
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'lsi.json')
      @lsi.storage = Classifier::Storage::File.new(path: path)

      @lsi.add_item('content', :category)
      @lsi.save_checkpoint('test')

      checkpoint_path = File.join(dir, 'lsi_checkpoint_test.json')

      assert_path_exists checkpoint_path

      @lsi.delete_checkpoint('test')

      refute_path_exists checkpoint_path
    end
  end

  def test_checkpoint_workflow
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'lsi.json')
      storage = Classifier::Storage::File.new(path: path)

      # First training session
      lsi1 = Classifier::LSI.new
      lsi1.storage = storage

      lsi1.add_item('dogs are loyal', :dog)
      lsi1.add_item('puppies are playful', :dog)
      lsi1.save_checkpoint('phase1')

      # Simulate restart - load from checkpoint
      lsi2 = Classifier::LSI.load_checkpoint(storage: storage, checkpoint_id: 'phase1')

      # Continue training
      lsi2.add_item('cats are independent', :cat)
      lsi2.add_item('kittens are curious', :cat)
      lsi2.save_checkpoint('phase2')

      # Load final checkpoint
      final = Classifier::LSI.load_checkpoint(storage: storage, checkpoint_id: 'phase2')

      # Should have all training
      assert_equal 4, final.items.size
      assert_equal 'dog', final.classify('loyal playful').to_s
      assert_equal 'cat', final.classify('independent curious').to_s
    end
  end
end
