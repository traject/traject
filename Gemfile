source 'https://rubygems.org'

# Specify your gem's dependencies in traject.gemspec

platforms :jruby do
 gem "marc-marc4j", ">=0.1.1"
end

gem "marc", ">= 0.7.1"
gem "hashie", ">= 2.0.5", "< 2.1" # used for Indexer#settings
gem "slop", ">= 3.4.5", "< 4.0"   # command line parsing
gem "yell" # logging

group :development do
  gem "nokogiri" # used only for rake tasks load_maps:
  gem "bundler", "~> 1.3"
  gem "rake"
  gem "minitest"
end

group :debug do
  #gem "ruby-debug"
end


