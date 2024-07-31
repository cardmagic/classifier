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

  def test_remove_category
    @classifier.train_interesting 'This is interesting content'
    @classifier.train_uninteresting 'This is uninteresting content'

    assert_equal %w[Interesting Uninteresting].sort, @classifier.categories.sort

    @classifier.remove_category 'Uninteresting'

    assert_equal ['Interesting'], @classifier.categories
  end

  def test_remove_nonexistent_category
    assert_raises(StandardError) do
      @classifier.remove_category 'NonexistentCategory'
    end
  end

  def test_remove_category_affects_classification
    @classifier.train_interesting 'This is interesting content'
    @classifier.train_uninteresting 'This is uninteresting content'

    assert_equal 'Uninteresting', @classifier.classify('This is uninteresting')

    @classifier.remove_category 'Uninteresting'

    assert_equal 'Interesting', @classifier.classify('This is uninteresting')
  end

  def test_remove_all_categories
    @classifier.remove_category 'Interesting'
    @classifier.remove_category 'Uninteresting'

    assert_empty @classifier.categories
  end

  def test_remove_and_add_category
    @classifier.remove_category 'Uninteresting'
    @classifier.add_category 'Neutral'

    assert_equal %w[Interesting Neutral].sort, @classifier.categories.sort
  end

  def test_remove_category_preserves_other_category_data
    @classifier.train_interesting 'This is interesting content'
    @classifier.train_uninteresting 'This is uninteresting content'

    interesting_classification = @classifier.classify('This is interesting')
    @classifier.remove_category 'Uninteresting'

    assert_equal interesting_classification, @classifier.classify('This is interesting')
  end

  def test_remove_category
    initial_total_words = @classifier.instance_variable_get(:@total_words)
    category_word_count = @classifier.instance_variable_get(:@category_word_count)['Interesting']

    @classifier.remove_category('Interesting')

    assert_nil @classifier.instance_variable_get(:@categories)['Interesting']
    assert_equal @classifier.instance_variable_get(:@category_counts)['Interesting'], 0
    assert_equal @classifier.instance_variable_get(:@category_word_count)['Interesting'], 0

    new_total_words = @classifier.instance_variable_get(:@total_words)
    assert_equal initial_total_words - category_word_count, new_total_words
  end

  def test_remove_category_updates_total_words_before_deletion
    initial_total_words = @classifier.instance_variable_get(:@total_words)
    category_word_count = @classifier.instance_variable_get(:@category_word_count)['Interesting']

    @classifier.remove_category('Interesting')

    new_total_words = @classifier.instance_variable_get(:@total_words)
    assert_equal initial_total_words - category_word_count, new_total_words
  end

  def test_remove_nonexistent_category
    assert_raises(StandardError, 'No such category: Nonexistent Category') do
      @classifier.remove_category('Nonexistent Category')
    end
  end
end
