Gem::Specification.new do |s|
  #### Basic information.

  s.name = 'classifier'
  s.version = PKG_VERSION
  s.version = "#{s.version}-alpha-#{ENV['TRAVIS_BUILD_NUMBER']}" if ENV['TRAVIS']
  s.summary = <<-EOF
   A general classifier module to allow Bayesian and other types of classifications.
  EOF
  s.description = <<-EOF
   A general classifier module to allow Bayesian and other types of classifications.
  EOF

  #### Which files are to be included in this gem?  Everything!  (Except CVS directories.)

  s.files = PKG_FILES

  #### Load-time details: library and application (you will need one or both).

  s.require_path = 'lib'
  s.autorequire = 'classifier'

  #### Documentation and testing.

  s.has_rdoc = true

  #### Dependencies and requirements.

  s.add_dependency('fast-stemmer', '>= 1.0.0')
  s.requirements << "A porter-stemmer module to split word stems."

  #### Author and project details.
  s.author = "Lucas Carlson"
  s.email = "lucas@rufy.com"
  s.homepage = "http://classifier.rufy.com/"
end
