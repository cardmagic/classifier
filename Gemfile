source 'https://rubygems.org'
gemspec

gem 'fast-stemmer'
gem 'matrix'
gem 'mutex_m'
gem 'ostruct'

group :test do
  gem 'simplecov', require: false
end

group :development do
  gem 'rubocop', require: false
  gem 'rubocop-minitest', require: false
  # steep's ffi dependency doesn't support Ruby 4.0 yet
  install_if -> { RUBY_VERSION < '4.0' } do
    gem 'steep', require: false
  end
end
