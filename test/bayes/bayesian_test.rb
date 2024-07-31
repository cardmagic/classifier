require_relative '../test_helper'

class BayesianTest < Minitest::Test
  def setup
    @classifier = Classifier::Bayes.new 'Interesting', 'Uninteresting'
  end

  def test_bad_training
    assert_raises(StandardError) { @classifier.train_no_category 'words' }
  end

  def test_bad_method
    assert_raises(NoMethodError) { @classifier.forget_everything_you_know '' }
  end

  def test_categories
    assert_equal %w[Interesting Uninteresting].sort, @classifier.categories.sort
  end

  def test_add_category
    @classifier.add_category 'Test'
    assert_equal %w[Test Interesting Uninteresting].sort, @classifier.categories.sort
  end

  def test_classification
    @classifier.train_interesting 'here are some good words. I hope you love them'
    @classifier.train_uninteresting 'here are some bad words, I hate you'
    assert_equal 'Uninteresting', @classifier.classify('I hate bad words and you')
  end

  def test_safari_animals
    bayes = Classifier::Bayes.new 'Lion', 'Elephant'
    bayes.train_lion 'lion'
    bayes.train_lion 'zebra'
    bayes.train_elephant 'elephant'
    bayes.train_elephant 'trunk'
    bayes.train_elephant 'tusk'

    assert_equal 'Lion', bayes.classify('zebra')
    assert_equal 'Elephant', bayes.classify('trunk')
    assert_equal 'Elephant', bayes.classify('tusk')
    assert_equal 'Lion', bayes.classify('lion')
    assert_equal 'Elephant', bayes.classify('elephant')
  end
end
