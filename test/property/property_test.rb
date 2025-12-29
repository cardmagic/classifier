require_relative '../test_helper'
require 'rantly'

class PropertyTest < Minitest::Test
  ITERATIONS = Integer(ENV.fetch('RANTLY_COUNT', 50))

  SAMPLE_WORDS = %w[
    apple banana cherry orange grape mango peach plum
    computer software hardware programming algorithm database
    running jumping swimming cycling hiking climbing skiing
    happy excited joyful peaceful calm relaxed content
    mountain river ocean forest desert valley meadow
  ].freeze

  def setup
    @classifier = Classifier::Bayes.new 'Spam', 'Ham'
    @classifier.train_spam 'buy now free offer limited time deal discount'
    @classifier.train_ham 'hello friend meeting project work schedule'
  end

  def random_alpha_string(min_len = 5, max_len = 100)
    Rantly { sized(range(min_len, max_len)) { string(:alpha) } }
  end

  def random_meaningful_text(word_count = 5)
    SAMPLE_WORDS.sample(word_count).join(' ')
  end

  def test_classification_is_deterministic
    ITERATIONS.times do
      random_text = random_alpha_string
      c1 = @classifier.classify(random_text)
      c2 = @classifier.classify(random_text)

      assert_equal c1, c2, "Classification should be deterministic for: #{random_text.inspect}"
    end
  end

  def test_classification_scores_are_deterministic
    ITERATIONS.times do
      random_text = random_alpha_string(10, 50)
      scores1 = @classifier.classifications(random_text)
      scores2 = @classifier.classifications(random_text)

      assert_equal scores1, scores2, 'Classification scores should be deterministic'
    end
  end

  def test_training_order_independence
    30.times do
      word_count = Rantly { range(3, 6) }
      texts = Array.new(word_count) { random_meaningful_text(5) }

      c1 = Classifier::Bayes.new 'A', 'B'
      c2 = Classifier::Bayes.new 'A', 'B'

      c1.train_b 'different category words'
      c2.train_b 'different category words'

      texts.each { |t| c1.train_a(t) }
      texts.shuffle.each { |t| c2.train_a(t) }

      test_phrase = 'test classification'
      scores1 = c1.classifications(test_phrase)
      scores2 = c2.classifications(test_phrase)

      assert_in_delta scores1['A'], scores2['A'], 0.0001,
                      'Training order should not affect classification scores'
      assert_in_delta scores1['B'], scores2['B'], 0.0001,
                      'Training order should not affect classification scores'
    end
  end

  def test_untrain_is_inverse_of_train
    30.times do
      text = random_meaningful_text(5)

      classifier = Classifier::Bayes.new 'Spam', 'Ham'
      classifier.train_spam 'initial training data here'
      classifier.train_ham 'other category data here'

      original_scores = classifier.classifications('test phrase')

      classifier.train_spam(text)
      classifier.untrain_spam(text)

      restored_scores = classifier.classifications('test phrase')

      assert_in_delta original_scores['Spam'], restored_scores['Spam'], 0.0001,
                      'Untrain should restore original state'
      assert_in_delta original_scores['Ham'], restored_scores['Ham'], 0.0001,
                      'Untrain should restore original state'
    end
  end

  def test_word_counts_never_negative
    30.times do
      train_text = random_meaningful_text(3)
      untrain_text = random_meaningful_text(8)

      classifier = Classifier::Bayes.new 'A', 'B'
      classifier.train_a train_text
      classifier.untrain_a untrain_text

      category_words = classifier.instance_variable_get(:@categories)[:A]

      category_words.each_value do |count|
        assert_operator count, :>=, 0, 'Word counts should never be negative'
      end

      total = classifier.instance_variable_get(:@total_words)

      assert_operator total, :>=, 0, 'Total words should never be negative'
    end
  end

  def test_category_counts_are_consistent
    20.times do
      classifier = Classifier::Bayes.new 'A', 'B'
      classifier.train_a 'single document'
      classifier.train_a 'another document'

      initial_count = classifier.instance_variable_get(:@category_counts)[:A]

      assert_equal 2, initial_count

      classifier.untrain_a 'some text'
      after_untrain = classifier.instance_variable_get(:@category_counts)[:A]

      assert_equal 1, after_untrain, 'Untrain should decrement category count'
    end
  end

  def test_classification_returns_valid_category
    ITERATIONS.times do
      random_text = Rantly { sized(range(1, 100)) { string } }
      result = @classifier.classify(random_text)

      assert_includes %w[Spam Ham], result,
                      'Classification must return a valid category'
    end
  end

  def test_classifications_contains_all_categories
    30.times do
      random_text = random_alpha_string(5, 50)
      scores = @classifier.classifications(random_text)

      assert_includes scores.keys, 'Spam', 'Should contain Spam category'
      assert_includes scores.keys, 'Ham', 'Should contain Ham category'
      assert_equal 2, scores.size, 'Should have exactly 2 categories'
    end
  end

  def test_log_probabilities_are_finite
    ITERATIONS.times do
      random_text = random_alpha_string
      scores = @classifier.classifications(random_text)

      scores.each do |category, score|
        assert_predicate score, :finite?,
                         "Score for #{category} should be finite, got: #{score}"
      end
    end
  end

  def test_multiple_training_equivalence
    20.times do
      text = random_meaningful_text(3)

      c1 = Classifier::Bayes.new 'A', 'B'
      c2 = Classifier::Bayes.new 'A', 'B'

      3.times { c1.train_a(text) }
      c2.train_a("#{text} #{text} #{text}")

      scores1 = c1.classifications('test')
      scores2 = c2.classifications('test')

      assert_in_delta scores1['A'], scores2['A'], 0.0001,
                      'Multiple trains should equal single train with repeated text'
    end
  end
end

class LSIPropertyTest < Minitest::Test
  def test_lsi_classification_is_deterministic
    tech_docs = [
      'This text deals with computers. Computers and programming.',
      'This document involves software development. Software!',
      'This text revolves around technology. Technology!'
    ]
    sports_docs = [
      'This text deals with sports. Sports and football.',
      'This document involves basketball. Basketball!',
      'This text revolves around athletics. Athletics!'
    ]

    20.times do
      lsi = Classifier::LSI.new
      tech_docs.each { |doc| lsi.add_item doc, 'Tech' }
      sports_docs.each { |doc| lsi.add_item doc, 'Sports' }

      test_doc = 'This is about programming and computers.'

      c1 = lsi.classify(test_doc)
      c2 = lsi.classify(test_doc)

      assert_equal c1, c2, 'LSI classification should be deterministic'
      assert_equal 'Tech', c1, 'Tech document should classify as Tech'
    end
  end

  def test_find_related_is_deterministic
    15.times do
      lsi = Classifier::LSI.new
      doc1 = 'This text deals with dogs. Dogs are great pets.'
      doc2 = 'This text involves cats. Cats are independent.'
      doc3 = 'This text revolves around dogs too. Dogs!'

      lsi << doc1
      lsi << doc2
      lsi << doc3

      related1 = lsi.find_related(doc1, 2)
      related2 = lsi.find_related(doc1, 2)

      assert_equal related1, related2, 'find_related should be deterministic'
    end
  end

  def test_search_is_deterministic
    15.times do
      lsi = Classifier::LSI.new
      lsi << 'This text deals with dogs. Dogs are loyal pets.'
      lsi << 'This text involves cats. Cats are curious animals.'
      lsi << 'This text revolves around birds. Birds can fly.'

      query = 'dogs pets'

      results1 = lsi.search(query, 2)
      results2 = lsi.search(query, 2)

      assert_equal results1, results2, 'Search should be deterministic'
    end
  end

  def test_lsi_handles_uncategorized_items
    lsi = Classifier::LSI.new
    lsi.add_item 'This text deals with technology. Technology!', 'Tech'
    lsi.add_item 'This text involves sports. Sports!', 'Sports'
    lsi << 'This is a random document about nothing.'

    result = lsi.classify('This is random content.')

    assert(result.nil? || result.is_a?(String),
           'Should return nil or a string category')
  end

  def test_lsi_rebuild_consistency
    10.times do
      lsi = Classifier::LSI.new(auto_rebuild: true)

      lsi.add_item 'This text deals with computers. Computers!', 'Tech'
      lsi.add_item 'This text involves sports. Sports!', 'Sports'

      lsi.add_item 'This text revolves around programming. Programming!', 'Tech'
      lsi.add_item 'This text involves football. Football!', 'Sports'

      test_text = 'This is about programming and computers.'
      result1 = lsi.classify(test_text)
      result2 = lsi.classify(test_text)

      assert_equal result1, result2, 'Classification should be deterministic after rebuild'
    end
  end
end

class MultiCategoryPropertyTest < Minitest::Test
  def test_category_operations_maintain_consistency
    20.times do
      category_name = "Category#{rand(1000)}"

      classifier = Classifier::Bayes.new 'Default'
      classifier.add_category(category_name)

      normalized_name = category_name.prepare_category_name.to_s

      assert_includes classifier.categories, normalized_name,
                      'Added category should be present'

      classifier.remove_category(category_name)

      refute_includes classifier.categories, normalized_name,
                      'Removed category should not be present'
    end
  end

  def test_training_data_isolation
    words_a = %w[apple banana cherry orange grape]
    words_b = %w[dog elephant fox giraffe horse]

    20.times do
      text1 = words_a.sample(3).join(' ')
      text2 = words_b.sample(3).join(' ')

      classifier = Classifier::Bayes.new 'A', 'B'
      classifier.train_a text1
      classifier.train_b text2

      category_a = classifier.instance_variable_get(:@categories)[:A]
      category_b = classifier.instance_variable_get(:@categories)[:B]

      text1.downcase.split.each do |word|
        next if word.length < 3

        stemmed = word.stem
        next unless category_a[stemmed.to_sym]

        refute category_b[stemmed.to_sym],
               'Words trained in A should not appear in B'
      end
    end
  end
end
