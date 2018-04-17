require_relative '../test_helper'

class BayesianTest < Minitest::Test
	def setup
		@classifier = Classifier::Bayes.new 'Interesting', 'Uninteresting'
	end

	def test_bad_training
		assert_raises(StandardError) { @classifier.train_no_category "words" }
	end

	def test_bad_method
		assert_raises(NoMethodError) { @classifier.forget_everything_you_know "" }
	end

	def test_categories
		assert_equal ['Interesting', 'Uninteresting'].sort, @classifier.categories.sort
	end

	def test_add_category
		@classifier.add_category 'Test'
		assert_equal ['Test', 'Interesting', 'Uninteresting'].sort, @classifier.categories.sort
	end

	def test_classification
		@classifier.train_interesting "here are some good words. I hope you love them"
		@classifier.train_uninteresting "here are some bad words, I hate you"
		assert_equal 'Uninteresting', @classifier.classify("I hate bad words and you")
	end
end
