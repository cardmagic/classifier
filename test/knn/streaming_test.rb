require_relative '../test_helper'
require 'stringio'

class KNNStreamingTest < Minitest::Test
  def test_train_from_stream_basic
    knn = Classifier::KNN.new
    knn.train_from_stream(:spam, StringIO.new("buy now cheap\nfree money\nlimited offer\n"))

    assert_equal 'spam', knn.classify('buy cheap free')
  end

  def test_train_from_stream_many_categories
    knn = Classifier::KNN.new
    knn.train_from_stream(
      spam: StringIO.new("buy now cheap\nfree money\nlimited offer\n"),
      ham: StringIO.new("hello friend\nmeeting tomorrow\nhello fellow\n")
    )

    assert_equal 'spam', knn.classify('free offer')
    assert_equal 'ham', knn.classify('hello')
  end

  def test_train_from_stream_invalid_io_type
    knn = Classifier::KNN.new
    assert_raises(StandardError) do
      knn.train_from_stream(spam: Object.new)
    end
  end
end
