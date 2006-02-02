# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2005 Lucas Carlson
# License::   LGPL

class String
   def summary( count=10, separator=" [...] " )
      perform_lsi split_sentences, count, separator
   end

   def paragraph_summary( count=1, separator=" [...] " )
      perform_lsi split_paragraphs, count, separator
   end

   def split_sentences
      split /(\.|\!|\?)/ # TODO: make this less primitive
   end
   
   def split_paragraphs
      split /(\n\n|\r\r|\r\n\r\n)/ # TODO: make this less primitive
   end
   
   private
   
   def perform_lsi(chunks, count, separator)
      lsi = Classifier::LSI.new :auto_rebuild => false
      chunks.each { |chunk| lsi << chunk unless chunk.strip.empty? || chunk.strip.split.size == 1 }
      lsi.build_index
      summaries = lsi.highest_relative_content count
      return summaries.reject { |chunk| !summaries.include? chunk }.map { |x| x.strip }.join(separator)
   end
end