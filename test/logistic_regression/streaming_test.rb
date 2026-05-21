require_relative '../test_helper'
require 'stringio'

class LogisticRegressionStreamingTest < Minitest::Test
  def test_train_from_stream_basic
    classifier = Classifier::LogisticRegression.new('Spam', 'Ham')
    classifier.train_from_stream(:spam, StringIO.new("buy now cheap\nfree money\nlimited offer\n"))
    classifier.fit

    assert_equal 'Spam', classifier.classify('buy cheap free')
  end

  def test_train_from_stream_many_categories
    classifier = Classifier::LogisticRegression.new('Spam', 'Ham')
    classifier.train_from_stream(
      spam: StringIO.new("buy now cheap\nfree money\nlimited offer\n"),
      ham: StringIO.new("hello friend\nmeeting tomorrow\n")
    )
    classifier.fit

    assert_equal 'Spam', classifier.classify('buy free')
    assert_equal 'Ham', classifier.classify('hello meeting')
  end

  def test_train_from_stream_invalid_io_type
    classifier = Classifier::LogisticRegression.new('Spam', 'Ham')
    assert_raises(StandardError) do
      classifier.train_from_stream(spam: Object.new)
    end
  end
end
