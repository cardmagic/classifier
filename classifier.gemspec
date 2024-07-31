Gem::Specification.new do |s|
  s.name        = 'classifier'
  s.version     = '1.4.4'
  s.summary     = 'A general classifier module to allow Bayesian and other types of classifications.'
  s.description = 'A general classifier module to allow Bayesian and other types of classifications.'
  s.author = 'Lucas Carlson'
  s.email = 'lucas@rufy.com'
  s.homepage = 'https://github.com/cardmagic/classifier'
  s.files = Dir['{lib}/**/*.rb', 'bin/*', 'LICENSE', '*.md', 'test/*']
  s.license = 'LGPL'

  s.add_dependency 'fast-stemmer', '~> 1.0'
  s.add_dependency 'mutex_m', '~> 0.2'
  s.add_dependency 'rake'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'rdoc'
end
