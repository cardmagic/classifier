# rbs_inline: enabled

# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2005 Lucas Carlson
# License::   LGPL

module Classifier
  class Bayes
    # @rbs @categories: Hash[Symbol, Hash[Symbol, Integer]]
    # @rbs @total_words: Integer
    # @rbs @category_counts: Hash[Symbol, Integer]
    # @rbs @category_word_count: Hash[Symbol, Integer]

    # The class can be created with one or more categories, each of which will be
    # initialized and given a training method. E.g.,
    #      b = Classifier::Bayes.new 'Interesting', 'Uninteresting', 'Spam'
    # @rbs (*String | Symbol) -> void
    def initialize(*categories)
      @categories = {}
      categories.each { |category| @categories[category.prepare_category_name] = {} }
      @total_words = 0
      @category_counts = Hash.new(0)
      @category_word_count = Hash.new(0)
    end

    # Provides a general training method for all categories specified in Bayes#new
    # For example:
    #     b = Classifier::Bayes.new 'This', 'That', 'the_other'
    #     b.train :this, "This text"
    #     b.train "that", "That text"
    #     b.train "The other", "The other text"
    #
    # @rbs (String | Symbol, String) -> void
    def train(category, text)
      category = category.prepare_category_name
      @category_counts[category] += 1
      text.word_hash.each do |word, count|
        @categories[category][word] ||= 0
        @categories[category][word] += count
        @total_words += count
        @category_word_count[category] += count
      end
    end

    # Provides a untraining method for all categories specified in Bayes#new
    # Be very careful with this method.
    #
    # For example:
    #     b = Classifier::Bayes.new 'This', 'That', 'the_other'
    #     b.train :this, "This text"
    #     b.untrain :this, "This text"
    #
    # @rbs (String | Symbol, String) -> void
    def untrain(category, text)
      category = category.prepare_category_name
      @category_counts[category] -= 1
      text.word_hash.each do |word, count|
        next unless @total_words >= 0

        orig = @categories[category][word] || 0
        @categories[category][word] ||= 0
        @categories[category][word] -= count
        if @categories[category][word] <= 0
          @categories[category].delete(word)
          count = orig
        end
        @category_word_count[category] -= count if @category_word_count[category] >= count
        @total_words -= count
      end
    end

    # Returns the scores in each category the provided +text+. E.g.,
    #    b.classifications "I hate bad words and you"
    #    =>  {"Uninteresting"=>-12.6997928013932, "Interesting"=>-18.4206807439524}
    # The largest of these scores (the one closest to 0) is the one picked out by #classify
    #
    # @rbs (String) -> Hash[String, Float]
    def classifications(text)
      words = text.word_hash.keys
      training_count = @category_counts.values.sum.to_f
      vocab_size = [@categories.values.flat_map(&:keys).uniq.size, 1].max

      @categories.to_h do |category, category_words|
        smoothed_total = ((@category_word_count[category] || 0) + vocab_size).to_f

        # Laplace smoothing: P(word|category) = (count + α) / (total + α * V)
        word_score = words.sum { |w| Math.log(((category_words[w] || 0) + 1) / smoothed_total) }
        prior_score = Math.log((@category_counts[category] || 0.1) / training_count)

        [category.to_s, word_score + prior_score]
      end
    end

    # Returns the classification of the provided +text+, which is one of the
    # categories given in the initializer. E.g.,
    #    b.classify "I hate bad words and you"
    #    =>  'Uninteresting'
    #
    # @rbs (String) -> String
    def classify(text)
      classifications(text).min_by { |a| -a[1] }[0]
    end

    #
    # Provides training and untraining methods for the categories specified in Bayes#new
    # For example:
    #     b = Classifier::Bayes.new 'This', 'That', 'the_other'
    #     b.train_this "This text"
    #     b.train_that "That text"
    #     b.untrain_that "That text"
    #     b.train_the_other "The other text"
    def method_missing(name, *args)
      return super unless name.to_s =~ /(un)?train_(\w+)/

      category = name.to_s.gsub(/(un)?train_(\w+)/, '\2').prepare_category_name
      raise StandardError, "No such category: #{category}" unless @categories.key?(category)

      method = name.to_s.start_with?('untrain_') ? :untrain : :train
      args.each { |text| send(method, category, text) }
    end

    # @rbs (Symbol, ?bool) -> bool
    def respond_to_missing?(name, include_private = false)
      name.to_s =~ /(un)?train_(\w+)/ || super
    end

    # Provides a list of category names
    # For example:
    #     b.categories
    #     =>   ['This', 'That', 'the_other']
    #
    # @rbs () -> Array[String]
    def categories
      @categories.keys.collect(&:to_s)
    end

    # Allows you to add categories to the classifier.
    # For example:
    #     b.add_category "Not spam"
    #
    # WARNING: Adding categories to a trained classifier will
    # result in an undertrained category that will tend to match
    # more criteria than the trained selective categories. In short,
    # try to initialize your categories at initialization.
    #
    # @rbs (String | Symbol) -> Hash[Symbol, Integer]
    def add_category(category)
      @categories[category.prepare_category_name] = {}
    end

    alias append_category add_category

    # Allows you to remove categories from the classifier.
    # For example:
    #     b.remove_category "Spam"
    #
    # WARNING: Removing categories from a trained classifier will
    # result in the loss of all training data for that category.
    # Make sure you really want to do this before calling this method.
    #
    # @rbs (String | Symbol) -> void
    def remove_category(category)
      category = category.prepare_category_name
      raise StandardError, "No such category: #{category}" unless @categories.key?(category)

      @total_words -= @category_word_count[category].to_i

      @categories.delete(category)
      @category_counts.delete(category)
      @category_word_count.delete(category)
    end
  end
end
