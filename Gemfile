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

# ruby-marc stopped supporting ruby 2.3 and 2.4 in newer 1.x versions,
# while we would still like to support those old versions. When running
# CI, run with older ruby-marc that still supports them.
ruby_version_parts = RUBY_VERSION.split(".")
if ruby_version_parts[0] == "2" && ruby_version_parts[1].to_i < 5
  gem "marc", "< 1.2.0"
end
