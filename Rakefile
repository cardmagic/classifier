require 'rubygems'
require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'
require 'rake/gempackagetask'
require 'rake/contrib/rubyforgepublisher'

PKG_FILES = FileList[
    "lib/**/*", "bin/*", "test/**/*", "[A-Z]*", "Rakefile", "html/**/*"
]

desc "Default Task"
task :default => [ :test ]

# Run the unit tests
desc "Run all unit tests"
Rake::TestTask.new("test") { |t|
  t.libs << "lib"
  t.pattern = 'test/*/*_test.rb'
  t.verbose = true
}

# Make a console, useful when working on tests
desc "Generate a test console"
task :console do
   verbose( false ) { sh "irb -I lib/ -r 'classifier'" }
end

# Genereate the RDoc documentation
desc "Create documentation"
Rake::RDocTask.new("doc") { |rdoc|
  rdoc.title = "Ruby Classifier - Bayesian and LSI classification library"
  rdoc.rdoc_dir = 'html'
  rdoc.rdoc_files.include('README')
  rdoc.rdoc_files.include('lib/**/*.rb')
}


desc "Report code statistics (KLOCs, etc) from the application"
task :stats do
  require 'code_statistics'
  CodeStatistics.new(
    ["Library", "lib"],
    ["Units", "test"]
  ).to_s
end

desc "Publish new documentation"
task :publish do
   `ssh rufy update-classifier-doc`
    Rake::RubyForgePublisher.new('classifier', 'cardmagic').upload
end

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name        = "classifier"
    gemspec.summary     = "Ruby Classifier - Bayesian and LSI classification library"
    gemspec.email       = "lucas@rufy.com"
    gemspec.homepage    = "https://github.com/cardmagic/classifier"
    gemspec.add_dependency('fast-stemmer', '>= 1.0.0')
    gemspec.autorequire = 'classifier'
    gemspec.has_rdoc    = true
  end
rescue LoadError
  puts "Jeweler not available. Install it with: gem install jeweler"
end
