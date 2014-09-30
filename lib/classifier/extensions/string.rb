# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2005 Lucas Carlson
# License::   LGPL
if RUBY_PLATFORM =~ /java/
  require 'stemmify'
else
  require 'fast_stemmer'
end
require 'classifier/extensions/word_hash'

class Object
	def prepare_category_name; to_s.gsub("_"," ").capitalize.intern end
end
