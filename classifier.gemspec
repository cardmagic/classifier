require_relative 'lib/classifier/version'

Gem::Specification.new do |s|
  s.name        = 'classifier'
  s.version     = Classifier::VERSION
  s.summary     = 'Text classification with Bayesian, LSI, Logistic Regression, kNN, and TF-IDF vectorization.'
  s.description = 'A Ruby library for text classification featuring Naive Bayes, LSI (Latent Semantic Indexing), ' \
                  'Logistic Regression, and k-Nearest Neighbors classifiers. Includes TF-IDF vectorization, ' \
                  'streaming/incremental training, pluggable persistence backends, thread safety, and a native ' \
                  'C extension for fast LSI operations.'
  s.author = 'Lucas Carlson'
  s.email = 'lucas@rufy.com'
  s.homepage = 'https://rubyclassifier.com'
  s.metadata = {
    'documentation_uri' => 'https://rubyclassifier.com/docs',
    'source_code_uri' => 'https://github.com/cardmagic/classifier',
    'bug_tracker_uri' => 'https://github.com/cardmagic/classifier/issues',
    'changelog_uri' => 'https://github.com/cardmagic/classifier/releases'
  }
  s.required_ruby_version = '>= 3.1'
  s.files = Dir['{lib,sig,exe}/**/*.{rb,rbs}', 'ext/**/*.{c,h,rb}', 'exe/*', 'bin/*', 'LICENSE', '*.md', 'test/*']
  s.bindir = 'exe'
  s.executables = ['classifier']
  s.extensions = ['ext/classifier/extconf.rb']
  s.license = 'LGPL'

  s.add_dependency 'fast-stemmer', '~> 1.0'
  s.add_dependency 'mutex_m', '~> 0.2'
  s.add_dependency 'rake'
  s.add_dependency 'matrix'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'rbs-inline'
  s.add_development_dependency 'rdoc'
  s.add_development_dependency 'rake-compiler'
end
