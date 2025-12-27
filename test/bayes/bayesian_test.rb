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

  def test_remove_category_check_counts
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

  # Untrain tests

  def test_untrain_basic
    @classifier.train_interesting 'good words'
    initial_total = @classifier.instance_variable_get(:@total_words)

    @classifier.untrain_interesting 'good words'

    new_total = @classifier.instance_variable_get(:@total_words)
    assert new_total < initial_total, 'Total words should decrease after untrain'
  end

  def test_untrain_with_train_method
    @classifier.train :interesting, 'hello world'
    @classifier.untrain :interesting, 'hello world'

    category_words = @classifier.instance_variable_get(:@categories)[:Interesting]
    assert_empty category_words, 'Category should have no words after untraining same text'
  end

  def test_untrain_dynamic_method
    @classifier.train_interesting 'dynamic method test'
    @classifier.untrain_interesting 'dynamic method test'

    category_words = @classifier.instance_variable_get(:@categories)[:Interesting]
    assert_empty category_words, 'Dynamic untrain should remove trained words'
  end

  def test_untrain_affects_classification
    # Train both categories with distinct words
    @classifier.train_interesting 'cats cats cats pets pets great'
    @classifier.train_uninteresting 'dogs dogs dogs animals bad'

    assert_equal 'Interesting', @classifier.classify('cats pets')

    # Untrain some of the interesting words, but keep category viable
    @classifier.untrain_interesting 'cats cats pets'

    # Now train more uninteresting with cats
    @classifier.train_uninteresting 'cats cats cats'

    # Classification should now favor uninteresting for 'cats'
    assert_equal 'Uninteresting', @classifier.classify('cats')
  end

  def test_untrain_decrements_category_count
    @classifier.train_interesting 'first document'
    @classifier.train_interesting 'second document'

    initial_count = @classifier.instance_variable_get(:@category_counts)[:Interesting]
    assert_equal 2, initial_count

    @classifier.untrain_interesting 'first document'

    new_count = @classifier.instance_variable_get(:@category_counts)[:Interesting]
    assert_equal 1, new_count
  end

  def test_untrain_removes_word_when_count_zero
    @classifier.train_interesting 'unique'

    category_words = @classifier.instance_variable_get(:@categories)[:Interesting]
    assert category_words.key?(:uniqu), 'Word should exist after training'

    @classifier.untrain_interesting 'unique'

    refute category_words.key?(:uniqu), 'Word should be removed when count reaches zero'
  end

  def test_untrain_partial_word_removal
    @classifier.train_interesting 'apple apple apple'
    @classifier.untrain_interesting 'apple'

    category_words = @classifier.instance_variable_get(:@categories)[:Interesting]
    assert_equal 2, category_words[:appl], 'Should have 2 remaining after untraining 1'
  end

  def test_untrain_more_than_trained
    @classifier.train_interesting 'word'
    @classifier.untrain_interesting 'word word word word word'

    category_words = @classifier.instance_variable_get(:@categories)[:Interesting]
    refute category_words.key?(:word), 'Word should be deleted, not go negative'

    total_words = @classifier.instance_variable_get(:@total_words)
    assert total_words >= 0, 'Total words should not go negative'
  end

  def test_untrain_nonexistent_words
    @classifier.train_interesting 'existing words'
    initial_total = @classifier.instance_variable_get(:@total_words)

    @classifier.untrain_interesting 'completely different text'

    new_total = @classifier.instance_variable_get(:@total_words)
    assert new_total <= initial_total, 'Should handle non-existent words gracefully'
  end

  def test_untrain_invalid_category
    assert_raises(StandardError) { @classifier.untrain_nonexistent 'words' }
  end

  def test_untrain_decrements_category_word_count
    @classifier.train_interesting 'hello world testing'
    initial_word_count = @classifier.instance_variable_get(:@category_word_count)[:Interesting]

    @classifier.untrain_interesting 'hello'

    new_word_count = @classifier.instance_variable_get(:@category_word_count)[:Interesting]
    assert new_word_count < initial_word_count, 'Category word count should decrease'
  end

  # Edge case tests

  def test_empty_string_training
    @classifier.train_interesting ''
    category_words = @classifier.instance_variable_get(:@categories)[:Interesting]
    assert_empty category_words, 'Empty string should not add any words'
  end

  def test_empty_string_classification
    @classifier.train_interesting 'good words here'
    @classifier.train_uninteresting 'bad words here'

    result = @classifier.classify('')
    assert_includes %w[Interesting Uninteresting], result, 'Should return a category even for empty string'
  end

  def test_unicode_text_training
    @classifier.train_interesting '日本語 chinese 中文 korean 한국어'
    @classifier.train_uninteresting 'plain english text only'

    # Unicode characters are treated as words if long enough
    category_words = @classifier.instance_variable_get(:@categories)[:Interesting]
    assert category_words.size > 0, 'Should store unicode words'
  end

  def test_emoji_training
    @classifier.train_interesting '😀 happy 🎉 celebration 🚀 rocket'
    @classifier.train_uninteresting 'sad 😢 crying 💔 heartbreak'

    result = @classifier.classify('happy celebration')
    assert_equal 'Interesting', result, 'Should handle emoji in text'
  end

  def test_special_characters_only
    @classifier.train_interesting '!@#$%^&*()'
    category_words = @classifier.instance_variable_get(:@categories)[:Interesting]
    # Special chars become symbols in word_hash, but clean_word_hash filters them
    assert_kind_of Hash, category_words
  end

  def test_very_long_text
    long_text = 'interesting ' * 10_000
    @classifier.train_interesting long_text
    @classifier.train_uninteresting 'boring text'

    total_words = @classifier.instance_variable_get(:@total_words)
    assert total_words > 0, 'Should handle very long text'

    result = @classifier.classify('interesting')
    assert_equal 'Interesting', result
  end

  def test_single_word_classification
    @classifier.train_interesting 'apple'
    @classifier.train_uninteresting 'banana'

    assert_equal 'Interesting', @classifier.classify('apple')
    assert_equal 'Uninteresting', @classifier.classify('banana')
  end

  def test_whitespace_only
    @classifier.train_interesting "   \t\n   "
    category_words = @classifier.instance_variable_get(:@categories)[:Interesting]
    assert_empty category_words, 'Whitespace-only should not add words'
  end

  def test_mixed_case_classification
    @classifier.train_interesting 'UPPERCASE lowercase MiXeD'
    @classifier.train_uninteresting 'different words here'

    # Words are downcased during training, so uppercase query should match
    result = @classifier.classify('uppercase lowercase')
    assert_equal 'Interesting', result, 'Should handle mixed case'
  end

  def test_numbers_in_text
    @classifier.train_interesting 'test123 456test 789'
    @classifier.train_uninteresting 'abc def ghi'

    result = @classifier.classify('test123')
    assert_equal 'Interesting', result, 'Should handle numbers in text'
  end
end
