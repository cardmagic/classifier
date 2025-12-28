require 'rake'
require 'rake/testtask'
require 'rdoc/task'

# Try to load rake-compiler for native extension support
begin
  require 'rake/extensiontask'
  Rake::ExtensionTask.new('classifier_ext') do |ext|
    ext.lib_dir = 'lib/classifier'
    ext.ext_dir = 'ext/classifier'
  end
  HAVE_EXTENSION = true
rescue LoadError
  HAVE_EXTENSION = false
end

desc 'Default Task'
task default: HAVE_EXTENSION ? %i[compile test] : [:test]

# Run the unit tests
desc 'Run all unit tests'
Rake::TestTask.new('test') do |t|
  t.libs << 'lib'
  t.pattern = 'test/*/*_test.rb'
  t.verbose = true
end

# Make a console, useful when working on tests
desc 'Generate a test console'
task :console do
  verbose(false) { sh "irb -I lib/ -r 'classifier'" }
end

# Genereate the RDoc documentation
desc 'Create documentation'
Rake::RDocTask.new('doc') do |rdoc|
  rdoc.title = 'Ruby Classifier - Bayesian and LSI classification library'
  rdoc.rdoc_dir = 'html'
  rdoc.rdoc_files.include('README.md')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

# Benchmarks
desc 'Run LSI benchmark with current configuration'
task :benchmark do
  ruby 'benchmark/lsi_benchmark.rb'
end

desc 'Run LSI benchmark comparing GSL vs Native Ruby'
task 'benchmark:compare' do
  ruby 'benchmark/lsi_benchmark.rb --compare'
end

desc 'Report code statistics (KLOCs, etc) from the application'
task :stats do
  require 'code_statistics'
  CodeStatistics.new(
    %w[Library lib],
    %w[Units test]
  ).to_s
end

desc 'Publish new documentation'
task :publish do
  `ssh rufy update-classifier-doc`
  Rake::RubyForgePublisher.new('classifier', 'cardmagic').upload
end
