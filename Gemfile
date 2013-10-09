source 'https://rubygems.org'


gem "marc", ">= 0.7.1"
gem "hashie", ">= 2.0.5", "< 2.1" # used for Indexer#settings
gem "slop", ">= 3.4.5", "< 4.0"   # command line parsing
gem "yell" # logging

platform :jruby do
  gem "marc-marc4j", ">=0.1.1"
end

group :development do
  gem "nokogiri" # used only for rake tasks load_maps:
  gem "bundler", "~> 1.3"
  gem "rake"
  gem "minitest"
end


group :debug do
  # gem "ruby-debug" # doesn't work under MRI 1.9 mode
end



