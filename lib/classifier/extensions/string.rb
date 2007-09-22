# Author::    Lucas Carlson  (mailto:lucas@rufy.com)
# Copyright:: Copyright (c) 2005 Lucas Carlson
# License::   LGPL

begin
	require 'stemmer'
rescue LoadError
	puts "Please install stemmer from http://rubyforge.org/projects/stemmer or 'gem install stemmer'"
	exit(-1)
end

require 'classifier/extensions/word_hash'

class Object
	def prepare_category_name; to_s.gsub("_"," ").capitalize.intern end
end
