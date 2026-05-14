require_relative '../test_helper'
require 'classifier/config'

class ConfigTest < Minitest::Test
  def teardown
    Classifier.config.min_word_length = 3
  end

  def test_configure
    Classifier.configure do |config|
      config.min_word_length = 1
    end

    assert_equal(1, Classifier.config.min_word_length)
  end

  def test_default
    config = Classifier::Config.new

    assert_equal(3, config.min_word_length)
  end
end
