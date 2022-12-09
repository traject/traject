# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'traject/version'

Gem::Specification.new do |spec|
  spec.name     = "traject"
  spec.version  = Traject::VERSION
  spec.authors  = ["Jonathan Rochkind", "Bill Dueber"]
  spec.email    = ["none@nowhere.org"]
  spec.summary  = %q{An easy to use, high-performance, flexible and extensible metadata transformation system, focused on library-archives-museums input, and indexing to Solr as output.}
  spec.homepage = "http://github.com/traject/traject"
  spec.license  = "MIT"

  # everything in git, but not ./index_bench/, cause that has some giant source files in there.
  spec.files         = `git ls-files`.split($/).find_all { |path| path !~ %r{^index_bench/} }
  spec.executables   = ["traject"]
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.extra_rdoc_files = spec.files.grep(%r{^doc/})


  spec.add_dependency "concurrent-ruby", ">= 0.8.0"
  spec.add_dependency "marc", "~> 1.0"

  spec.add_dependency "hashie", ">= 3.1", "< 6" # used for Indexer#settings
  spec.add_dependency "slop", "~> 4.0" # command line parsing
  spec.add_dependency "yell" # logging
  spec.add_dependency "dot-properties", ">= 0.1.1" # reading java style .properties
  spec.add_dependency "httpclient", "~> 2.5"
  spec.add_dependency "http", ">= 3.0", "< 6" # used in oai_pmh_reader, may use more extensively in future instead of httpclient
  spec.add_dependency 'marc-fastxmlwriter', '~>1.0' # fast marc->xml
  spec.add_dependency "nokogiri", "~> 1.9" # NokogiriIndexer

  spec.add_development_dependency 'bundler', '>= 1.7', '< 3'

  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rspec-mocks", '~> 3.4'
end
