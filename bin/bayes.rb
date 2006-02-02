#!/usr/bin/env ruby

begin
	require 'rubygems'
	require_gem 'classifier'
rescue
	require 'classifier'
end

require 'madeleine'

m = SnapshotMadeleine.new(File.expand_path("~/.bayes_data")) {
	Classifier::Bayes.new 'Interesting', 'Uninteresting'
}

case ARGV[0]
when "add"
	case ARGV[1].downcase
	when "interesting"
		m.system.train_interesting File.open(ARGV[2]).read
		puts "#{ARGV[2]} has been classified as interesting"
	when "uninteresting"
		m.system.train_uninteresting File.open(ARGV[2]).read
		puts "#{ARGV[2]} has been classified as uninteresting"
	else
		puts "Invalid category: choose between interesting and uninteresting"
		exit(1)
	end
when "classify"
	puts m.system.classify(File.open(ARGV[1]).read)
else
	puts "Invalid option: choose add [category] [file] or clasify [file]"
	exit(-1)
end

m.take_snapshot
