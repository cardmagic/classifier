require_relative '../test_helper'
require 'stringio'
require 'tempfile'

class BayesStreamingTest < Minitest::Test
  def setup
    @classifier = Classifier::Bayes.new('Spam', 'Ham')
  end

  # train_from_stream tests

  def test_train_from_stream_basic
    io = StringIO.new("buy now cheap\nfree money\nlimited offer\n")
    @classifier.train_from_stream(:spam, io)

    # Should have trained 3 documents
    assert_equal 'Spam', @classifier.classify('buy cheap free')
  end

  def test_train_from_stream_empty_io
    io = StringIO.new('')
    @classifier.train_from_stream(:spam, io)

    # No documents trained, classifier should still work
    assert_includes @classifier.categories, 'Spam'
  end

  def test_train_from_stream_single_line
    io = StringIO.new("this is spam content\n")
    @classifier.train_from_stream(:spam, io)

    # Train some ham to make classification meaningful
    @classifier.train(:ham, 'this is normal email')

    result = @classifier.classify('spam content')
    assert_equal 'Spam', result
  end

  def test_train_from_stream_with_batch_size
    lines = (1..50).map { |i| "document number #{i} with some content" }
    io = StringIO.new(lines.join("\n"))

    batches_processed = 0
    @classifier.train_from_stream(:spam, io, batch_size: 10) do |progress|
      batches_processed = progress.current_batch
    end

    assert_equal 5, batches_processed
  end

  def test_train_from_stream_progress_tracking
    lines = (1..25).map { |i| "line #{i}" }
    io = StringIO.new(lines.join("\n"))

    completed_values = []
    @classifier.train_from_stream(:spam, io, batch_size: 10) do |progress|
      completed_values << progress.completed
    end

    assert_equal [10, 20, 25], completed_values
  end

  def test_train_from_stream_with_progress_block
    io = StringIO.new("doc1\ndoc2\ndoc3\n")
    progress_received = nil

    @classifier.train_from_stream(:spam, io, batch_size: 2) do |progress|
      progress_received = progress
    end

    assert_instance_of Classifier::Streaming::Progress, progress_received
    assert_equal 3, progress_received.completed
  end

  def test_train_from_stream_invalid_category
    io = StringIO.new("some content\n")

    assert_raises(StandardError) do
      @classifier.train_from_stream(:nonexistent, io)
    end
  end

  def test_train_from_stream_marks_dirty
    io = StringIO.new("content\n")
    refute @classifier.dirty?

    @classifier.train_from_stream(:spam, io)
    assert @classifier.dirty?
  end

  def test_train_from_stream_with_file
    Tempfile.create(['corpus', '.txt']) do |file|
      file.puts 'spam message one'
      file.puts 'spam message two'
      file.puts 'spam message three'
      file.flush
      file.rewind

      @classifier.train_from_stream(:spam, file)
    end

    @classifier.train(:ham, 'normal message here')
    assert_equal 'Spam', @classifier.classify('spam message')
  end

  # train_batch tests

  def test_train_batch_positional_style
    documents = ['buy now', 'free money', 'limited offer']
    @classifier.train_batch(:spam, documents)

    @classifier.train(:ham, 'hello friend')
    assert_equal 'Spam', @classifier.classify('buy free limited')
  end

  def test_train_batch_keyword_style
    spam_docs = ['buy now', 'free money']
    ham_docs = ['hello friend', 'meeting tomorrow']

    @classifier.train_batch(spam: spam_docs, ham: ham_docs)

    assert_equal 'Spam', @classifier.classify('buy free')
    assert_equal 'Ham', @classifier.classify('hello meeting')
  end

  def test_train_batch_with_batch_size
    documents = (1..100).map { |i| "document #{i}" }

    batches = 0
    @classifier.train_batch(:spam, documents, batch_size: 25) do |_progress|
      batches += 1
    end

    assert_equal 4, batches
  end

  def test_train_batch_progress_tracking
    documents = (1..30).map { |i| "doc #{i}" }

    completed_values = []
    @classifier.train_batch(:spam, documents, batch_size: 10) do |progress|
      completed_values << progress.completed
    end

    assert_equal [10, 20, 30], completed_values
  end

  def test_train_batch_progress_percent
    documents = (1..100).map { |i| "doc #{i}" }

    percent_values = []
    @classifier.train_batch(:spam, documents, batch_size: 25) do |progress|
      percent_values << progress.percent
    end

    assert_equal [25.0, 50.0, 75.0, 100.0], percent_values
  end

  def test_train_batch_empty_array
    @classifier.train_batch(:spam, [])
    # Should not raise, classifier should be unchanged
    assert_includes @classifier.categories, 'Spam'
  end

  def test_train_batch_invalid_category
    assert_raises(StandardError) do
      @classifier.train_batch(:nonexistent, ['doc'])
    end
  end

  def test_train_batch_marks_dirty
    refute @classifier.dirty?
    @classifier.train_batch(:spam, ['content'])
    assert @classifier.dirty?
  end

  def test_train_batch_multiple_categories
    @classifier.train_batch(
      spam: ['buy now', 'free offer'],
      ham: ['hello', 'meeting']
    )

    assert_equal 'Spam', @classifier.classify('buy free')
    assert_equal 'Ham', @classifier.classify('hello meeting')
  end

  # Equivalence tests

  def test_train_batch_equivalent_to_train
    classifier1 = Classifier::Bayes.new('Spam', 'Ham')
    classifier2 = Classifier::Bayes.new('Spam', 'Ham')

    documents = ['buy now cheap', 'free money fast', 'limited time offer']

    # Train with regular train
    documents.each { |doc| classifier1.train(:spam, doc) }

    # Train with train_batch
    classifier2.train_batch(:spam, documents)

    # Both should classify the same
    test_doc = 'buy cheap free limited'
    assert_equal classifier1.classify(test_doc), classifier2.classify(test_doc)

    # Classifications should be identical
    assert_equal classifier1.classifications(test_doc), classifier2.classifications(test_doc)
  end

  def test_train_from_stream_equivalent_to_train
    classifier1 = Classifier::Bayes.new('Spam', 'Ham')
    classifier2 = Classifier::Bayes.new('Spam', 'Ham')

    documents = ['buy now cheap', 'free money fast', 'limited time offer']

    # Train with regular train
    documents.each { |doc| classifier1.train(:spam, doc) }

    # Train with train_from_stream
    io = StringIO.new(documents.join("\n"))
    classifier2.train_from_stream(:spam, io)

    # Both should classify the same
    test_doc = 'buy cheap free limited'
    assert_equal classifier1.classify(test_doc), classifier2.classify(test_doc)
  end

  # Checkpoint tests

  def test_save_checkpoint
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'classifier.json')
      @classifier.storage = Classifier::Storage::File.new(path: path)

      @classifier.train(:spam, 'buy now cheap')
      @classifier.save_checkpoint('50pct')

      checkpoint_path = File.join(dir, 'classifier_checkpoint_50pct.json')
      assert File.exist?(checkpoint_path)
    end
  end

  def test_load_checkpoint
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'classifier.json')
      storage = Classifier::Storage::File.new(path: path)
      @classifier.storage = storage

      @classifier.train(:spam, 'buy now cheap')
      @classifier.save_checkpoint('halfway')

      # Load from checkpoint
      loaded = Classifier::Bayes.load_checkpoint(storage: storage, checkpoint_id: 'halfway')

      # Should have the same training
      assert_equal @classifier.classify('buy cheap'), loaded.classify('buy cheap')
    end
  end

  def test_list_checkpoints
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'classifier.json')
      @classifier.storage = Classifier::Storage::File.new(path: path)

      @classifier.train(:spam, 'content')
      @classifier.save_checkpoint('10pct')
      @classifier.save_checkpoint('50pct')
      @classifier.save_checkpoint('90pct')

      checkpoints = @classifier.list_checkpoints
      assert_equal %w[10pct 50pct 90pct], checkpoints.sort
    end
  end

  def test_delete_checkpoint
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'classifier.json')
      @classifier.storage = Classifier::Storage::File.new(path: path)

      @classifier.train(:spam, 'content')
      @classifier.save_checkpoint('test')

      checkpoint_path = File.join(dir, 'classifier_checkpoint_test.json')
      assert File.exist?(checkpoint_path)

      @classifier.delete_checkpoint('test')
      refute File.exist?(checkpoint_path)
    end
  end

  def test_save_checkpoint_requires_storage
    assert_raises(ArgumentError) do
      @classifier.save_checkpoint('test')
    end
  end

  def test_checkpoint_workflow
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'classifier.json')
      storage = Classifier::Storage::File.new(path: path)

      # First training session
      classifier1 = Classifier::Bayes.new('Spam', 'Ham')
      classifier1.storage = storage

      classifier1.train(:spam, 'buy now')
      classifier1.train(:spam, 'free money')
      classifier1.save_checkpoint('phase1')

      # Simulate restart - load from checkpoint
      classifier2 = Classifier::Bayes.load_checkpoint(storage: storage, checkpoint_id: 'phase1')

      # Continue training
      classifier2.train(:ham, 'hello friend')
      classifier2.train(:ham, 'meeting tomorrow')
      classifier2.save_checkpoint('phase2')

      # Load final checkpoint
      final = Classifier::Bayes.load_checkpoint(storage: storage, checkpoint_id: 'phase2')

      # Should have all training
      assert_equal 'Spam', final.classify('buy free')
      assert_equal 'Ham', final.classify('hello meeting')
    end
  end
end
