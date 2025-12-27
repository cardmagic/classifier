# rbs_inline: enabled

# Author::    David Fayram  (mailto:dfayram@lensmen.net)
# Copyright:: Copyright (c) 2005 David Fayram II
# License::   LGPL

module Classifier
  # This class keeps a word => index mapping. It is used to map stemmed words
  # to dimensions of a vector.
  class WordList
    # @rbs @location_table: Hash[Symbol, Integer]

    # @rbs () -> void
    def initialize
      @location_table = {}
    end

    # Adds a word (if it is new) and assigns it a unique dimension.
    #
    # @rbs (Symbol) -> Integer?
    def add_word(word)
      term = word
      @location_table[term] = @location_table.size unless @location_table[term]
    end

    # Returns the dimension of the word or nil if the word is not in the space.
    #
    # @rbs (Symbol) -> Integer?
    def [](lookup)
      term = lookup
      @location_table[term]
    end

    # @rbs (Integer) -> Symbol?
    def word_for_index(ind)
      @location_table.invert[ind]
    end

    # Returns the number of words mapped.
    #
    # @rbs () -> Integer
    def size
      @location_table.size
    end
  end
end
