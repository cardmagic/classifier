# Author::    David Fayram  (mailto:dfayram@lensmen.net)
# Copyright:: Copyright (c) 2005 David Fayram II
# License::   LGPL

module Classifier

# This is an internal data structure class for the LSI node. Save for 
# raw_vector_with, it should be fairly straightforward to understand.
# You should never have to use it directly.
  class ContentNode
    attr_accessor :raw_vector, :raw_norm, 
                  :lsi_vector, :lsi_norm,
                  :categories   
    
    attr_reader :word_hash
    # If text_proc is not specified, the source will be duck-typed
    # via source.to_s
    def initialize( word_hash, *categories )
      @categories = categories || []
      @word_hash = word_hash
    end
   
    # Use this to fetch the appropriate search vector.
    def search_vector
      @lsi_vector || @raw_vector
    end
    
    # Use this to fetch the appropriate search vector in normalized form.
    def search_norm
      @lsi_norm || @raw_norm
    end
   
    # Creates the raw vector out of word_hash using word_list as the
    # key for mapping the vector space.
    def raw_vector_with( word_list )
      if $GSL
         vec = GSL::Vector.alloc(word_list.size)
      else
         vec = Array.new(word_list.size, 0)
      end

      @word_hash.each_key do |word|
        vec[word_list[word]] = @word_hash[word] if word_list[word]
      end

      # Perform the scaling transform
      total_words = vec.sum
      total_unique_words = vec.count{|word| word != 0}

      # Perform first-order association transform if this vector has more
      # than one word in it.
      if total_words > 1.0 && total_unique_words > 1
        weighted_total = 0.0
        vec.each do |term|
          if ( term > 0 )
            weighted_total += (( term / total_words ) * Math.log( term / total_words ))
          end
        end
        vec = vec.collect { |val| Math.log( val + 1 ) / -weighted_total }
      end

      if $GSL
         @raw_norm   = vec.normalize
         @raw_vector = vec
      else
         @raw_norm   = Vector[*vec].normalize
         @raw_vector = Vector[*vec]
      end
    end
  end  
  
end
