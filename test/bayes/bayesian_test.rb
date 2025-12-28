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
    assert_equal 0, @classifier.instance_variable_get(:@category_counts)['Interesting']
    assert_equal 0, @classifier.instance_variable_get(:@category_word_count)['Interesting']

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

    assert_operator new_total, :<, initial_total, 'Total words should decrease after untrain'
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

    assert_operator total_words, :>=, 0, 'Total words should not go negative'
  end

  def test_untrain_nonexistent_words
    @classifier.train_interesting 'existing words'
    initial_total = @classifier.instance_variable_get(:@total_words)

    @classifier.untrain_interesting 'completely different text'

    new_total = @classifier.instance_variable_get(:@total_words)

    assert_operator new_total, :<=, initial_total, 'Should handle non-existent words gracefully'
  end

  def test_untrain_invalid_category
    assert_raises(StandardError) { @classifier.untrain_nonexistent 'words' }
  end

  def test_untrain_decrements_category_word_count
    @classifier.train_interesting 'hello world testing'
    initial_word_count = @classifier.instance_variable_get(:@category_word_count)[:Interesting]

    @classifier.untrain_interesting 'hello'

    new_word_count = @classifier.instance_variable_get(:@category_word_count)[:Interesting]

    assert_operator new_word_count, :<, initial_word_count, 'Category word count should decrease'
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

    assert_predicate category_words.size, :positive?, 'Should store unicode words'
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

    assert_predicate total_words, :positive?, 'Should handle very long text'

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

  # Laplace smoothing tests

  def test_laplace_smoothing_unseen_words
    # Train with some words, then classify with unseen word
    # Laplace smoothing should give unseen words a non-zero probability
    # that scales with vocabulary size
    @classifier.train_interesting 'apple banana cherry'
    @classifier.train_uninteresting 'dog elephant fox'

    # "zebra" is unseen - should still get valid scores
    scores = @classifier.classifications('zebra')

    scores.each_value do |score|
      assert_predicate score, :finite?, 'Score should be finite with Laplace smoothing'
      refute_predicate score, :zero?, 'Score should be non-zero with Laplace smoothing'
    end
  end

  def test_laplace_smoothing_consistency
    # With proper Laplace smoothing, the probability of an unseen word
    # should be α / (total + α * vocab_size)
    # This should be consistent across categories with same training size
    classifier = Classifier::Bayes.new 'A', 'B'
    classifier.train_a 'word1 word2 word3'
    classifier.train_b 'word4 word5 word6'

    scores = classifier.classifications('unseenword')

    # Both categories have same word count, so unseen word scores should be equal
    assert_in_delta scores['A'], scores['B'], 0.01,
                    'Equal-sized categories should give equal scores for unseen words'
  end

  def test_laplace_smoothing_vocabulary_scaling
    # The smoothing should account for vocabulary size
    # Larger vocabulary = smaller probability for each unseen word
    small_vocab = Classifier::Bayes.new 'Cat', 'Dog'
    small_vocab.train_cat 'meow purr'
    small_vocab.train_dog 'bark woof'

    large_vocab = Classifier::Bayes.new 'Cat', 'Dog'
    large_vocab.train_cat 'meow purr hiss scratch climb jump pounce stalk hunt sleep'
    large_vocab.train_dog 'bark woof growl fetch run play chase guard protect howl'

    small_scores = small_vocab.classifications('unknown')
    large_scores = large_vocab.classifications('unknown')

    # With proper smoothing, larger vocabulary should give lower (more negative) scores
    # for unseen words because probability mass is spread across more terms
    assert_operator small_scores['Cat'], :>, large_scores['Cat'],
                    'Larger vocabulary should give lower scores for unseen words'
  end

  def test_laplace_smoothing_seen_words_also_smoothed
    # Proper Laplace smoothing applies to ALL words, not just unseen ones
    # P(word|cat) = (count + α) / (total + α * V), not count / total
    classifier = Classifier::Bayes.new 'A', 'B'
    classifier.train_a 'test'
    classifier.train_b 'other'

    # With proper smoothing, seen word probability should include α adjustment
    # The word "test" appears once in A with total=1, vocab=2
    # Proper: (1 + 1) / (1 + 1*2) = 2/3
    # Current: 1 / 1 = 1.0 (no smoothing applied to seen words)

    scores = classifier.classifications('test')

    # Score for A should reflect smoothed probability, not raw count
    # log(2/3) ≈ -0.405, not log(1) = 0
    # The word score plus prior should not equal just the prior
    prior_only_score = Math.log(0.5) # equal priors

    refute_in_delta scores['A'], prior_only_score, 0.01,
                    'Seen word score should include smoothing adjustment, not raw probability'
  end

  def test_laplace_smoothing_denominator_includes_vocabulary
    # The denominator should be (total + α * vocab_size), not just total
    # This test verifies that adding more vocabulary affects all probabilities
    classifier1 = Classifier::Bayes.new 'Spam', 'Ham'
    classifier1.train_spam 'buy now'
    classifier1.train_ham 'hello friend'

    classifier2 = Classifier::Bayes.new 'Spam', 'Ham'
    classifier2.train_spam 'buy now'
    classifier2.train_ham 'hello friend goodbye see you later take care'

    # Same query word "buy" - should have different probabilities
    # because vocabulary size differs (affecting denominator)
    scores1 = classifier1.classifications('buy')
    scores2 = classifier2.classifications('buy')

    # With proper smoothing, larger vocab in classifier2 means
    # the probability of "buy" in Spam is lower (spread across more terms)
    refute_in_delta scores1['Spam'], scores2['Spam'], 0.1,
                    'Vocabulary size should affect word probabilities in denominator'
  end

  # Save/Load tests

  def test_as_json
    @classifier.train_interesting 'good words here'
    @classifier.train_uninteresting 'bad words there'

    data = @classifier.as_json

    assert_instance_of Hash, data
    assert_equal 1, data[:version]
    assert_equal 'bayes', data[:type]
    assert_includes data[:categories].keys, 'Interesting'
    assert_includes data[:categories].keys, 'Uninteresting'
  end

  def test_to_json
    @classifier.train_interesting 'good words here'
    @classifier.train_uninteresting 'bad words there'

    json = @classifier.to_json
    data = JSON.parse(json)

    assert_equal 1, data['version']
    assert_equal 'bayes', data['type']
    assert_includes data['categories'].keys, 'Interesting'
    assert_includes data['categories'].keys, 'Uninteresting'
  end

  def test_from_json_with_string
    @classifier.train_interesting 'good words here'
    @classifier.train_uninteresting 'bad words there'

    json = @classifier.to_json
    loaded = Classifier::Bayes.from_json(json)

    assert_equal @classifier.categories.sort, loaded.categories.sort
    assert_equal @classifier.classify('good words'), loaded.classify('good words')
    assert_equal @classifier.classify('bad words'), loaded.classify('bad words')
  end

  def test_from_json_with_hash
    @classifier.train_interesting 'good words here'
    @classifier.train_uninteresting 'bad words there'

    # Use as_json to get a hash, then convert keys to strings (as would happen from JSON.parse)
    hash = JSON.parse(@classifier.to_json)
    loaded = Classifier::Bayes.from_json(hash)

    assert_equal @classifier.categories.sort, loaded.categories.sort
    assert_equal @classifier.classify('good words'), loaded.classify('good words')
    assert_equal @classifier.classify('bad words'), loaded.classify('bad words')
  end

  def test_from_json_invalid_type
    invalid_json = { version: 1, type: 'invalid' }.to_json

    assert_raises(ArgumentError) { Classifier::Bayes.from_json(invalid_json) }
  end

  def test_save_and_load
    @classifier.train_interesting 'good words here'
    @classifier.train_uninteresting 'bad words there'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'classifier.json')
      @classifier.save(path)

      assert_path_exists path, 'Save should create file'

      loaded = Classifier::Bayes.load(path)

      assert_equal @classifier.categories.sort, loaded.categories.sort
      assert_equal @classifier.classify('good'), loaded.classify('good')
    end
  end

  def test_save_load_preserves_training_state
    @classifier.train_interesting 'apple banana cherry'
    @classifier.train_uninteresting 'dog elephant fox'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'classifier.json')
      @classifier.save(path)
      loaded = Classifier::Bayes.load(path)

      # Verify classifications match
      assert_equal @classifier.classifications('apple'), loaded.classifications('apple')
      assert_equal @classifier.classifications('dog'), loaded.classifications('dog')
    end
  end

  def test_loaded_classifier_can_continue_training
    @classifier.train_interesting 'initial training'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'classifier.json')
      @classifier.save(path)
      loaded = Classifier::Bayes.load(path)

      # Continue training on loaded classifier
      loaded.train_interesting 'more interesting content'
      loaded.train_uninteresting 'boring content here'

      assert_equal 'Interesting', loaded.classify('interesting content')
      assert_equal 'Uninteresting', loaded.classify('boring content')
    end
  end
end
