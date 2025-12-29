Gem::Specification.new do |s|
  s.name        = 'classifier'
  s.version     = '2.1.0'
  s.summary     = 'Text classification with Bayesian, LSI, and k-Nearest Neighbors algorithms.'
  s.description = 'A Ruby library for text classification using Bayesian, LSI (Latent Semantic Indexing), and k-Nearest Neighbors (kNN) algorithms. Includes native C extension for fast LSI operations.'
  s.author = 'Lucas Carlson'
  s.email = 'lucas@rufy.com'
  s.homepage = 'https://rubyclassifier.com'
  s.metadata = {
    'documentation_uri' => 'https://rubyclassifier.com/docs',
    'source_code_uri' => 'https://github.com/cardmagic/classifier',
    'bug_tracker_uri' => 'https://github.com/cardmagic/classifier/issues',
    'changelog_uri' => 'https://github.com/cardmagic/classifier/releases'
  }
  s.files = Dir['{lib,sig}/**/*.{rb,rbs}', 'ext/**/*.{c,h,rb}', 'bin/*', 'LICENSE', '*.md', 'test/*']
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
