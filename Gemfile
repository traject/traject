source 'https://rubygems.org'

# Specify your gem's dependencies in traject.gemspec
gemspec

group :development do
  gem "webmock", "~> 3.4"
end

group :debug do
  gem "ruby-debug", :platform => "jruby"
  gem "byebug", :platform => "mri"
end

# No longer in our gemspec, but we need it for testing MARC under JRuby.
gem "traject-marc4j_reader", "~> 1.0"
