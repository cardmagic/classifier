#!/usr/bin/env ruby

begin
        require 'rubygems'
        require_gem 'classifier'
rescue
        require 'classifier'
end

require 'open-uri'

num = ARGV[1].to_i
num = num < 1 ? 10 : num

text = open(ARGV.first).read
puts text.gsub(/<[^>]+>/,"").gsub(/[\s]+/," ").summary(num)
