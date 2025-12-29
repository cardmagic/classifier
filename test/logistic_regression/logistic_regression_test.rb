require_relative '../test_helper'

class LogisticRegressionTest < Minitest::Test
  def setup
    @classifier = Classifier::LogisticRegression.new 'Spam', 'Ham'
  end

  # Initialization tests

  def test_requires_at_least_two_categories
    assert_raises(ArgumentError) { Classifier::LogisticRegression.new 'Only' }
  end

  def test_accepts_symbols_and_strings
    classifier1 = Classifier::LogisticRegression.new :spam, :ham
    classifier2 = Classifier::LogisticRegression.new 'Spam', 'Ham'

    assert_equal %w[Spam Ham].sort, classifier1.categories.sort
    assert_equal %w[Spam Ham].sort, classifier2.categories.sort
  end

  def test_custom_hyperparameters
    classifier = Classifier::LogisticRegression.new(
      :spam, :ham,
      learning_rate: 0.01,
      regularization: 0.1,
      max_iterations: 50,
      tolerance: 1e-6
    )

    assert_instance_of Classifier::LogisticRegression, classifier
  end

  def test_categories
    assert_equal %w[Spam Ham].sort, @classifier.categories.sort
  end

  # Training tests

  def test_train_with_positional_arguments
    @classifier.train :spam, 'Buy now! Free money!'
    @classifier.train :ham, 'Hello friend, meeting tomorrow'

    assert_equal 'Spam', @classifier.classify('Buy free money')
    assert_equal 'Ham', @classifier.classify('Hello meeting friend')
  end

  def test_train_with_keyword_arguments
    @classifier.train(spam: 'Buy now! Free money!')
    @classifier.train(ham: 'Hello friend, meeting tomorrow')

    assert_equal 'Spam', @classifier.classify('Buy free money')
    assert_equal 'Ham', @classifier.classify('Hello meeting friend')
  end

  def test_train_with_array_value
    @classifier.train(spam: ['Buy now!', 'Free money!', 'Click here!'])
    @classifier.train(ham: 'Normal email content')

    assert_equal 'Spam', @classifier.classify('Buy click free')
  end

  def test_train_with_multiple_categories
    @classifier.train(
      spam: ['Buy now!', 'Free money!'],
      ham: ['Hello friend', 'Meeting tomorrow']
    )

    assert_equal 'Spam', @classifier.classify('Buy free')
    assert_equal 'Ham', @classifier.classify('Hello meeting')
  end

  def test_train_dynamic_method
    @classifier.train_spam 'Buy now! Free money!'
    @classifier.train_ham 'Hello friend'

    assert_equal 'Spam', @classifier.classify('Buy free money')
    assert_equal 'Ham', @classifier.classify('Hello friend')
  end

  def test_train_invalid_category
    assert_raises(StandardError) { @classifier.train(:invalid, 'text') }
    assert_raises(StandardError) { @classifier.train_invalid 'text' }
  end

  # Classification tests

  def test_classify_basic
    @classifier.train_spam 'Buy now! Free money! Limited offer!'
    @classifier.train_ham 'Hello, how are you? Meeting tomorrow.'

    assert_equal 'Spam', @classifier.classify('Free money offer')
    assert_equal 'Ham', @classifier.classify('Hello, how are you?')
  end

  def test_classify_with_more_training_data
    # Spam examples
    @classifier.train(spam: [
      'Buy now and save!',
      'Free money waiting for you',
      'Click here for amazing deals',
      'Limited time offer expires soon',
      'Congratulations you won a prize'
    ])

    # Ham examples
    @classifier.train(ham: [
      'Meeting scheduled for tomorrow at 10am',
      'Please review the attached document',
      'Can we discuss the project timeline?',
      'Thanks for your help yesterday',
      'Looking forward to seeing you'
    ])

    assert_equal 'Spam', @classifier.classify('Free prize money')
    assert_equal 'Ham', @classifier.classify('Project meeting tomorrow')
  end

  def test_classifications_returns_scores
    @classifier.train_spam 'spam words'
    @classifier.train_ham 'ham words'

    scores = @classifier.classifications('spam words')

    assert_instance_of Hash, scores
    assert_includes scores.keys, 'Spam'
    assert_includes scores.keys, 'Ham'
    scores.each_value { |v| assert_kind_of Numeric, v }
  end

  # Probability tests

  def test_probabilities_sum_to_one
    @classifier.train_spam 'spam words here'
    @classifier.train_ham 'ham words here'

    probs = @classifier.probabilities('test words')

    assert_in_delta 1.0, probs.values.sum, 0.001
  end

  def test_probabilities_are_between_zero_and_one
    @classifier.train_spam 'spam words here'
    @classifier.train_ham 'ham words here'

    probs = @classifier.probabilities('test words')

    probs.each_value do |prob|
      assert_operator prob, :>=, 0.0
      assert_operator prob, :<=, 1.0
    end
  end

  def test_probabilities_reflect_confidence
    @classifier.train(spam: ['spam spam spam'] * 10)
    @classifier.train(ham: ['ham ham ham'] * 10)

    spam_probs = @classifier.probabilities('spam spam spam')
    ham_probs = @classifier.probabilities('ham ham ham')

    assert_operator spam_probs['Spam'], :>, 0.5, 'Spam text should have high spam probability'
    assert_operator ham_probs['Ham'], :>, 0.5, 'Ham text should have high ham probability'
  end

  # Feature weights tests

  def test_weights_returns_hash
    @classifier.train_spam 'buy free money'
    @classifier.train_ham 'hello friend meeting'

    weights = @classifier.weights(:spam)

    assert_instance_of Hash, weights
    refute_empty weights
  end

  def test_weights_sorted_by_importance
    @classifier.train_spam 'spam spam spam important'
    @classifier.train_ham 'ham ham ham'

    weights = @classifier.weights(:spam)
    values = weights.values

    # Should be sorted by absolute value (descending)
    sorted_by_abs = values.sort_by { |v| -v.abs }
    assert_equal sorted_by_abs, values
  end

  def test_weights_with_limit
    @classifier.train_spam 'one two three four five'
    @classifier.train_ham 'six seven eight nine ten'

    weights = @classifier.weights(:spam, limit: 3)

    assert_equal 3, weights.size
  end

  def test_weights_invalid_category
    @classifier.train_spam 'spam'
    @classifier.train_ham 'ham'

    assert_raises(StandardError) { @classifier.weights(:invalid) }
  end

  # Fitted state tests

  def test_fitted_state
    refute_predicate @classifier, :fitted?

    @classifier.train_spam 'spam'
    @classifier.train_ham 'ham'

    refute_predicate @classifier, :fitted?

    @classifier.classify('test')

    assert_predicate @classifier, :fitted?
  end

  def test_fit_explicitly
    @classifier.train_spam 'spam'
    @classifier.train_ham 'ham'

    result = @classifier.fit

    assert_same @classifier, result
    assert_predicate @classifier, :fitted?
  end

  def test_auto_fit_on_classify
    @classifier.train_spam 'spam'
    @classifier.train_ham 'ham'

    refute_predicate @classifier, :fitted?
    @classifier.classify('test')
    assert_predicate @classifier, :fitted?
  end

  def test_auto_fit_on_probabilities
    @classifier.train_spam 'spam'
    @classifier.train_ham 'ham'

    refute_predicate @classifier, :fitted?
    @classifier.probabilities('test')
    assert_predicate @classifier, :fitted?
  end

  # Multi-class tests

  def test_three_class_classification
    classifier = Classifier::LogisticRegression.new :positive, :negative, :neutral

    classifier.train(positive: ['great amazing wonderful love happy'])
    classifier.train(negative: ['terrible awful hate bad angry'])
    classifier.train(neutral: ['okay average normal regular'])

    assert_equal 'Positive', classifier.classify('great love happy')
    assert_equal 'Negative', classifier.classify('terrible hate angry')
    assert_equal 'Neutral', classifier.classify('normal regular okay')
  end

  def test_multi_class_probabilities_sum_to_one
    classifier = Classifier::LogisticRegression.new :a, :b, :c, :d

    classifier.train(a: 'alpha', b: 'beta', c: 'gamma', d: 'delta')

    probs = classifier.probabilities('test')

    assert_in_delta 1.0, probs.values.sum, 0.001
  end

  # Serialization tests

  def test_as_json
    @classifier.train_spam 'spam words'
    @classifier.train_ham 'ham words'
    @classifier.fit

    data = @classifier.as_json

    assert_equal 1, data[:version]
    assert_equal 'logistic_regression', data[:type]
    assert_includes data[:categories], 'Spam'
    assert_includes data[:categories], 'Ham'
    assert_instance_of Hash, data[:weights]
    assert_instance_of Hash, data[:bias]
  end

  def test_to_json
    @classifier.train_spam 'spam words'
    @classifier.train_ham 'ham words'
    @classifier.fit

    json = @classifier.to_json
    data = JSON.parse(json)

    assert_equal 'logistic_regression', data['type']
  end

  def test_from_json_with_string
    @classifier.train_spam 'spam words'
    @classifier.train_ham 'ham words'

    json = @classifier.to_json
    loaded = Classifier::LogisticRegression.from_json(json)

    assert_equal @classifier.categories.sort, loaded.categories.sort
    assert_equal @classifier.classify('spam'), loaded.classify('spam')
    assert_equal @classifier.classify('ham'), loaded.classify('ham')
  end

  def test_from_json_with_hash
    @classifier.train_spam 'spam words'
    @classifier.train_ham 'ham words'

    hash = JSON.parse(@classifier.to_json)
    loaded = Classifier::LogisticRegression.from_json(hash)

    assert_equal @classifier.categories.sort, loaded.categories.sort
  end

  def test_from_json_invalid_type
    invalid_json = { version: 1, type: 'invalid' }.to_json

    assert_raises(ArgumentError) { Classifier::LogisticRegression.from_json(invalid_json) }
  end

  def test_save_and_load_file
    @classifier.train_spam 'spam words'
    @classifier.train_ham 'ham words'

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'classifier.json')
      @classifier.save_to_file(path)

      assert_path_exists path

      loaded = Classifier::LogisticRegression.load_from_file(path)

      assert_equal @classifier.categories.sort, loaded.categories.sort
      assert_equal @classifier.classify('spam'), loaded.classify('spam')
    end
  end

  def test_loaded_classifier_preserves_predictions
    @classifier.train(spam: ['buy free money offer'] * 5)
    @classifier.train(ham: ['hello meeting project friend'] * 5)

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'classifier.json')
      @classifier.save_to_file(path)
      loaded = Classifier::LogisticRegression.load_from_file(path)

      # Check that loaded classifier makes same predictions
      test_texts = ['buy free', 'hello meeting', 'money offer', 'project friend']
      test_texts.each do |text|
        assert_equal @classifier.classify(text), loaded.classify(text)
      end
    end
  end

  # Marshal tests

  def test_marshal_dump_and_load
    @classifier.train_spam 'spam words'
    @classifier.train_ham 'ham words'
    @classifier.fit

    dumped = Marshal.dump(@classifier)
    loaded = Marshal.load(dumped)

    assert_equal @classifier.categories.sort, loaded.categories.sort
    assert_equal @classifier.classify('spam'), loaded.classify('spam')
    assert_equal @classifier.classify('ham'), loaded.classify('ham')
  end

  # Dirty flag tests

  def test_dirty_flag_after_training
    refute_predicate @classifier, :dirty?

    @classifier.train_spam 'spam'

    assert_predicate @classifier, :dirty?
  end

  def test_dirty_flag_cleared_after_save
    @classifier.train_spam 'spam'
    @classifier.train_ham 'ham'

    assert_predicate @classifier, :dirty?

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'classifier.json')
      @classifier.save_to_file(path)

      refute_predicate @classifier, :dirty?
    end
  end

  # Edge case tests

  def test_empty_string_training
    @classifier.train_spam ''
    @classifier.train_ham 'ham words'
    @classifier.fit

    # Should not crash
    result = @classifier.classify('test')
    assert_includes @classifier.categories, result
  end

  def test_empty_string_classification
    @classifier.train_spam 'spam words'
    @classifier.train_ham 'ham words'

    result = @classifier.classify('')

    assert_includes @classifier.categories, result
  end

  def test_unicode_text
    @classifier.train_spam 'spam japonais 日本語'
    @classifier.train_ham 'ham chinese 中文'

    # Should handle unicode without crashing
    result = @classifier.classify('日本語 test')
    assert_includes @classifier.categories, result
  end

  def test_single_word_documents
    @classifier.train_spam 'spam'
    @classifier.train_ham 'ham'

    assert_equal 'Spam', @classifier.classify('spam')
    assert_equal 'Ham', @classifier.classify('ham')
  end

  def test_very_long_text
    long_spam = 'spam buy free money ' * 100
    long_ham = 'hello meeting project ' * 100

    @classifier.train_spam long_spam
    @classifier.train_ham long_ham

    assert_equal 'Spam', @classifier.classify('buy free money')
  end

  def test_special_characters
    @classifier.train_spam 'Buy! @#$% now!!!'
    @classifier.train_ham 'Hello... how are you???'

    # Should not crash on special characters
    @classifier.classify('!@#$%^&*()')
  end

  # Numerical stability tests

  def test_softmax_numerical_stability
    # Train with many samples to potentially create large scores
    100.times do
      @classifier.train_spam 'spam spam spam spam spam'
      @classifier.train_ham 'ham ham ham ham ham'
    end

    probs = @classifier.probabilities('spam spam spam')

    # Should not be NaN or Inf
    probs.each_value do |p|
      refute_predicate p, :nan?
      refute_predicate p, :infinite?
    end
  end

  # Regularization tests

  def test_regularization_prevents_overfitting
    # Without regularization, weights could become very large
    classifier = Classifier::LogisticRegression.new(
      :spam, :ham,
      regularization: 1.0  # Strong regularization
    )

    classifier.train_spam 'unique_spam_word'
    classifier.train_ham 'unique_ham_word'
    classifier.fit

    weights = classifier.weights(:spam)

    # With strong regularization, weights should be relatively small
    weights.each_value do |w|
      assert_operator w.abs, :<, 10.0, 'Weights should be constrained by regularization'
    end
  end

  # Convergence tests

  def test_convergence_with_separable_data
    # Clear separation between classes should converge quickly
    @classifier.train(spam: ['spam spam spam'] * 20)
    @classifier.train(ham: ['ham ham ham'] * 20)

    # Should be able to perfectly classify training data
    probs = @classifier.probabilities('spam spam spam')
    assert_operator probs['Spam'], :>, 0.9
  end

  # respond_to? tests

  def test_respond_to_train_methods
    assert_respond_to @classifier, :train_spam
    assert_respond_to @classifier, :train_ham
    # train_* methods respond true (dynamic methods), but raise on invalid categories
    assert_respond_to @classifier, :train_invalid
    refute_respond_to @classifier, :invalid_method
  end
end
