# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2005 Lucas Carlson
# License::   LGPL

module Classifier
  class Bayes
    # The class can be created with one or more categories, each of which will be
    # initialized and given a training method. E.g.,
    #      b = Classifier::Bayes.new 'Interesting', 'Uninteresting', 'Spam'
    def initialize(*categories)
      @categories = {}
      categories.each { |category| @categories[category.prepare_category_name] = {} }
      @total_words = 0
      @category_counts = Hash.new(0)
      @category_word_count = Hash.new(0)
    end

    #
    # Provides a general training method for all categories specified in Bayes#new
    # For example:
    #     b = Classifier::Bayes.new 'This', 'That', 'the_other'
    #     b.train :this, "This text"
    #     b.train "that", "That text"
    #     b.train "The other", "The other text"
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

    #
    # Provides a untraining method for all categories specified in Bayes#new
    # Be very careful with this method.
    #
    # For example:
    #     b = Classifier::Bayes.new 'This', 'That', 'the_other'
    #     b.train :this, "This text"
    #     b.untrain :this, "This text"
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

    #
    # Returns the scores in each category the provided +text+. E.g.,
    #    b.classifications "I hate bad words and you"
    #    =>  {"Uninteresting"=>-12.6997928013932, "Interesting"=>-18.4206807439524}
    # The largest of these scores (the one closest to 0) is the one picked out by #classify
    def classifications(text)
      score = {}
      word_hash = text.word_hash
      training_count = @category_counts.values.inject { |x, y| x + y }.to_f
      @categories.each do |category, category_words|
        score[category.to_s] = 0
        total = (@category_word_count[category] || 1).to_f
        word_hash.each_key do |word|
          s = category_words.key?(word) ? category_words[word] : 0.1
          score[category.to_s] += Math.log(s / total)
        end
        # now add prior probability for the category
        s = @category_counts.key?(category) ? @category_counts[category] : 0.1
        score[category.to_s] += Math.log(s / training_count)
      end
      score
    end

    #
    # Returns the classification of the provided +text+, which is one of the
    # categories given in the initializer. E.g.,
    #    b.classify "I hate bad words and you"
    #    =>  'Uninteresting'
    def classify(text)
      (classifications(text).sort_by { |a| -a[1] })[0][0]
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
      category = name.to_s.gsub(/(un)?train_(\w+)/, '\2').prepare_category_name
      if @categories.key?(category)
        args.each do |text|
          if name.to_s.start_with?('untrain_')
            untrain(category, text)
          else
            train(category, text)
          end
        end
      elsif name.to_s =~ /(un)?train_(\w+)/
        raise StandardError, "No such category: #{category}"
      else
        super
      end
    end

    #
    # Provides a list of category names
    # For example:
    #     b.categories
    #     =>   ['This', 'That', 'the_other']
    def categories # :nodoc:
      @categories.keys.collect(&:to_s)
    end

    #
    # Allows you to add categories to the classifier.
    # For example:
    #     b.add_category "Not spam"
    #
    # WARNING: Adding categories to a trained classifier will
    # result in an undertrained category that will tend to match
    # more criteria than the trained selective categories. In short,
    # try to initialize your categories at initialization.
    def add_category(category)
      @categories[category.prepare_category_name] = {}
    end

    alias append_category add_category

    #
    # Allows you to remove categories from the classifier.
    # For example:
    #     b.remove_category "Spam"
    #
    # WARNING: Removing categories from a trained classifier will
    # result in the loss of all training data for that category.
    # Make sure you really want to do this before calling this method.
    def remove_category(category)
      category = category.prepare_category_name
      raise StandardError, "No such category: #{category}" unless @categories.key?(category)

      @categories.delete(category)
      @category_counts.delete(category)
      @category_word_count.delete(category)
      @total_words -= @category_word_count[category].to_i
    end
  end
end
