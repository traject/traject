source 'https://rubygems.org'

# Specify your gem's dependencies in traject.gemspec
gemspec

group :development do
  gem "nokogiri" # used only for rake tasks load_maps:
  gem "webmock", "~> 3.4"
end

group :debug do
  gem "ruby-debug", :platform => "jruby"
  gem "byebug", :platform => "mri"
end
