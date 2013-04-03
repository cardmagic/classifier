# encoding: utf-8

require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  gem.name = "classifier"
  gem.homepage = "http://classifier.rufy.com"
  gem.license = "MIT"
  gem.summary = %Q{A general classifier module to allow Bayesian and other types of classifications.}
  gem.description = %Q{A general classifier module to allow Bayesian and other types of classifications.}
  gem.email = "lucas@rufy.com"
  gem.authors = ["Lucas Carlson"]
end
Jeweler::RubygemsDotOrgTasks.new

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

task :default => :test

require 'yard'
YARD::Rake::YardocTask.new
