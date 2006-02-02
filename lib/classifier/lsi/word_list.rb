# Author::    David Fayram  (mailto:dfayram@lensmen.net)
# Copyright:: Copyright (c) 2005 David Fayram II
# License::   LGPL

module Classifier  
  # This class keeps a word => index mapping. It is used to map stemmed words
  # to dimensions of a vector.
    
  class WordList
    def initialize
      @location_table = Hash.new
    end
    
    # Adds a word (if it is new) and assigns it a unique dimension.
    def add_word(word)
      term = word
      @location_table[term] = @location_table.size unless @location_table[term]
    end
    
    # Returns the dimension of the word or nil if the word is not in the space.
    def [](lookup)
      term = lookup
      @location_table[term]
    end
    
    def word_for_index(ind)
      @location_table.invert[ind]
    end
    
    # Returns the number of words mapped.
    def size
      @location_table.size
    end
    
  end
end
