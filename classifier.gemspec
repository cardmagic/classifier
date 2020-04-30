Gem::Specification.new do |s|
  s.name        = 'classifier'
  s.version     = '1.3.5'
  s.summary     = 'A general classifier module to allow Bayesian and other types of classifications.'
  s.description = 'A general classifier module to allow Bayesian and other types of classifications.'
  s.author = 'Lucas Carlson'
  s.email = 'lucas@rufy.com'
  s.homepage = 'https://github.com/cardmagic/classifier'
  s.files        = Dir["{lib}/**/*.rb", "bin/*", "LICENSE", "*.md"]
  s.license = 'LGPL'

  s.add_dependency 'fast-stemmer', '~> 1.0.0'
  # mathn deprecated and removed in >= 2.5
  s.add_dependency 'mathn' if RUBY_VERSION >= '2.5'
  # cmath moved to gem, mathn depends on cmath, but won't be updated due to deprecation
  s.add_dependency 'cmath' if RUBY_VERSION >= '2.7'
  s.add_dependency 'rake'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'rdoc'
end
