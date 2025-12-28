require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'
  add_group 'Bayes', 'lib/classifier/bayes.rb'
  add_group 'LSI', 'lib/classifier/lsi'
  add_group 'Extensions', 'lib/classifier/extensions'
  enable_coverage :branch
end

$LOAD_PATH.unshift("#{File.dirname(__FILE__)}/../lib")

require 'minitest'
require 'minitest/autorun'
require 'tmpdir'
require 'json'
require 'classifier'
