require_relative '../test_helper'
require 'stringio'

class ProgressTest < Minitest::Test
  def test_initialization_with_defaults
    progress = Classifier::Streaming::Progress.new

    assert_equal 0, progress.completed
    assert_nil progress.total
    assert_instance_of Time, progress.start_time
  end

  def test_initialization_with_total
    progress = Classifier::Streaming::Progress.new(total: 100)

    assert_equal 0, progress.completed
    assert_equal 100, progress.total
  end

  def test_initialization_with_completed
    progress = Classifier::Streaming::Progress.new(total: 100, completed: 50)

    assert_equal 50, progress.completed
    assert_equal 100, progress.total
  end

  def test_percent_with_known_total
    progress = Classifier::Streaming::Progress.new(total: 100, completed: 25)

    assert_in_delta(25.0, progress.percent)
  end

  def test_percent_with_fractional_value
    progress = Classifier::Streaming::Progress.new(total: 3, completed: 1)

    assert_in_delta(33.33, progress.percent)
  end

  def test_percent_with_unknown_total
    progress = Classifier::Streaming::Progress.new
    progress.completed = 50

    assert_nil progress.percent
  end

  def test_percent_with_zero_total
    progress = Classifier::Streaming::Progress.new(total: 0)

    assert_nil progress.percent
  end

  def test_elapsed_time
    progress = Classifier::Streaming::Progress.new
    sleep 0.01

    assert_operator progress.elapsed, :>=, 0.01
    assert_operator progress.elapsed, :<, 1
  end

  def test_rate_calculation
    progress = Classifier::Streaming::Progress.new(completed: 0)
    sleep 0.01 # Ensure some time passes
    progress.completed = 100
    # Rate should be roughly 100 / elapsed (approximately 10000/s)
    rate = progress.rate

    assert_predicate rate, :positive?
  end

  def test_rate_with_zero_elapsed
    # This is tricky to test since time always passes,
    # but rate should handle edge cases gracefully
    progress = Classifier::Streaming::Progress.new
    rate = progress.rate
    # Rate is 0 when completed is 0
    assert_in_delta(0.0, rate)
  end

  def test_eta_with_known_total
    progress = Classifier::Streaming::Progress.new(total: 100, completed: 50)
    sleep 0.01 # Ensure some time passes
    eta = progress.eta

    assert_instance_of Float, eta
    assert_operator eta, :>=, 0
  end

  def test_eta_with_unknown_total
    progress = Classifier::Streaming::Progress.new(completed: 50)

    assert_nil progress.eta
  end

  def test_eta_when_complete
    progress = Classifier::Streaming::Progress.new(total: 100, completed: 100)
    sleep 0.01

    assert_in_delta(0.0, progress.eta)
  end

  def test_eta_with_zero_rate
    progress = Classifier::Streaming::Progress.new(total: 100, completed: 0)

    assert_nil progress.eta
  end

  def test_complete_when_finished
    progress = Classifier::Streaming::Progress.new(total: 100, completed: 100)

    assert_predicate progress, :complete?
  end

  def test_complete_when_not_finished
    progress = Classifier::Streaming::Progress.new(total: 100, completed: 50)

    refute_predicate progress, :complete?
  end

  def test_complete_with_unknown_total
    progress = Classifier::Streaming::Progress.new(completed: 100)

    refute_predicate progress, :complete?
  end

  def test_to_h
    progress = Classifier::Streaming::Progress.new(total: 100, completed: 50)
    hash = progress.to_h

    assert_equal 50, hash[:completed]
    assert_equal 100, hash[:total]
    assert_in_delta(50.0, hash[:percent])
    assert_instance_of Float, hash[:elapsed]
    assert_instance_of Float, hash[:rate]
  end

  def test_completed_is_mutable
    progress = Classifier::Streaming::Progress.new(total: 100)

    assert_equal 0, progress.completed

    progress.completed = 25

    assert_equal 25, progress.completed

    progress.completed += 25

    assert_equal 50, progress.completed
  end

  def test_current_batch_tracking
    progress = Classifier::Streaming::Progress.new(total: 100)

    assert_equal 0, progress.current_batch

    progress.current_batch = 5

    assert_equal 5, progress.current_batch
  end
end

class LineReaderTest < Minitest::Test
  def test_each_line
    io = StringIO.new("line1\nline2\nline3\n")
    reader = Classifier::Streaming::LineReader.new(io)

    lines = reader.each.to_a

    assert_equal %w[line1 line2 line3], lines
  end

  def test_each_line_removes_trailing_newlines
    io = StringIO.new("line1\nline2\r\nline3")
    reader = Classifier::Streaming::LineReader.new(io)

    lines = reader.each.to_a
    # chomp removes both \n and \r\n
    assert_equal %w[line1 line2 line3], lines
  end

  def test_each_with_block
    io = StringIO.new("a\nb\nc\n")
    reader = Classifier::Streaming::LineReader.new(io)

    collected = reader.map(&:upcase)

    assert_equal %w[A B C], collected
  end

  def test_enumerable_methods
    io = StringIO.new("1\n2\n3\n")
    reader = Classifier::Streaming::LineReader.new(io)

    # LineReader includes Enumerable
    assert_equal %w[1 2 3], reader.first(3)
  end

  def test_each_batch_default_size
    lines = (1..250).map { |i| "line#{i}" }.join("\n")
    io = StringIO.new(lines)
    reader = Classifier::Streaming::LineReader.new(io)

    batches = reader.each_batch.to_a

    assert_equal 3, batches.size
    assert_equal 100, batches[0].size
    assert_equal 100, batches[1].size
    assert_equal 50, batches[2].size
  end

  def test_each_batch_custom_size
    lines = (1..25).map { |i| "line#{i}" }.join("\n")
    io = StringIO.new(lines)
    reader = Classifier::Streaming::LineReader.new(io, batch_size: 10)

    batches = reader.each_batch.to_a

    assert_equal 3, batches.size
    assert_equal 10, batches[0].size
    assert_equal 10, batches[1].size
    assert_equal 5, batches[2].size
  end

  def test_each_batch_with_block
    io = StringIO.new("a\nb\nc\nd\ne\n")
    reader = Classifier::Streaming::LineReader.new(io, batch_size: 2)

    collected = []
    reader.each_batch { |batch| collected << batch }

    assert_equal [%w[a b], %w[c d], ['e']], collected
  end

  def test_each_batch_exact_multiple
    lines = (1..10).map { |i| "line#{i}" }.join("\n")
    io = StringIO.new(lines)
    reader = Classifier::Streaming::LineReader.new(io, batch_size: 5)

    batches = reader.each_batch.to_a

    assert_equal 2, batches.size
    assert_equal 5, batches[0].size
    assert_equal 5, batches[1].size
  end

  def test_each_batch_empty_io
    io = StringIO.new('')
    reader = Classifier::Streaming::LineReader.new(io)

    batches = reader.each_batch.to_a

    assert_empty batches
  end

  def test_batch_size_reader
    reader = Classifier::Streaming::LineReader.new(StringIO.new(''), batch_size: 50)

    assert_equal 50, reader.batch_size
  end

  def test_estimate_line_count_with_seekable_io
    # Create a file-like StringIO
    lines = "short\nmedium line\nlonger line here\n"
    io = StringIO.new(lines)

    reader = Classifier::Streaming::LineReader.new(io)
    estimate = reader.estimate_line_count(sample_size: 3)

    # Should be close to 3 lines
    assert_instance_of Integer, estimate
    assert_predicate estimate, :positive?
  end

  def test_estimate_line_count_preserves_position
    lines = "a\nb\nc\nd\ne\n"
    io = StringIO.new(lines)
    io.gets # Read one line, position is now after "a\n"
    original_pos = io.pos

    reader = Classifier::Streaming::LineReader.new(io)
    reader.estimate_line_count

    assert_equal original_pos, io.pos
  end
end

class StreamingModuleTest < Minitest::Test
  def test_default_batch_size
    assert_equal 100, Classifier::Streaming::DEFAULT_BATCH_SIZE
  end

  class DummyClassifier
    include Classifier::Streaming

    attr_accessor :storage
  end

  def test_train_from_stream_raises_not_implemented
    classifier = DummyClassifier.new
    io = StringIO.new("test\n")

    assert_raises(NotImplementedError) do
      classifier.train_from_stream(:category, io)
    end
  end

  def test_train_batch_raises_not_implemented
    classifier = DummyClassifier.new

    assert_raises(NotImplementedError) do
      classifier.train_batch(:category, %w[doc1 doc2])
    end
  end

  def test_save_checkpoint_requires_storage
    classifier = DummyClassifier.new

    assert_raises(ArgumentError) do
      classifier.save_checkpoint('test')
    end
  end

  def test_list_checkpoints_requires_storage
    classifier = DummyClassifier.new

    assert_raises(ArgumentError) do
      classifier.list_checkpoints
    end
  end

  def test_delete_checkpoint_requires_storage
    classifier = DummyClassifier.new

    assert_raises(ArgumentError) do
      classifier.delete_checkpoint('test')
    end
  end
end

class StreamingEnforcementTest < Minitest::Test
  # Dynamically discover all classifier/vectorizer classes by looking for
  # classes that define `classify` (classifiers) or `transform` (vectorizers)
  CLASSIFIERS = Classifier.constants.filter_map do |const|
    klass = Classifier.const_get(const)
    next unless klass.is_a?(Class)
    klass if klass.method_defined?(:classify) || klass.method_defined?(:transform)
  end.freeze

  STREAMING_METHODS = %i[
    train_from_stream
    train_batch
    save_checkpoint
    list_checkpoints
    delete_checkpoint
  ].freeze

  def test_classifiers_discovered
    assert CLASSIFIERS.size >= 5, "Expected at least 5 classifiers, found: #{CLASSIFIERS.map(&:name)}"
  end

  CLASSIFIERS.each do |klass|
    define_method("test_#{klass.name.split('::').last.downcase}_includes_streaming") do
      assert klass.include?(Classifier::Streaming),
             "#{klass} must include Classifier::Streaming"
    end

    STREAMING_METHODS.each do |method|
      define_method("test_#{klass.name.split('::').last.downcase}_responds_to_#{method}") do
        assert klass.method_defined?(method) || klass.private_method_defined?(method),
               "#{klass} must respond to #{method}"
      end
    end
  end
end
