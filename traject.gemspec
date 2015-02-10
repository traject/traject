# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'traject/version'

Gem::Specification.new do |spec|
  spec.name          = "traject"
  spec.version       = Traject::VERSION
  spec.authors       = ["Jonathan Rochkind", "Bill Dueber"]
  spec.email         = ["none@nowhere.org"]
  spec.summary       = %q{Index MARC to Solr; or generally process source records to hash-like structures}
  spec.homepage      = "http://github.com/traject-project/traject"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = ["traject"]
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.extra_rdoc_files = spec.files.grep(%r{^doc/})


  spec.add_dependency "concurrent-ruby", ">= 0.8.0"
  spec.add_dependency "marc", "~> 1.0"

  spec.add_dependency "hashie", "~> 3.1"            # used for Indexer#settings
  spec.add_dependency "slop", ">= 3.4.5", "< 4.0"   # command line parsing
  spec.add_dependency "yell"                        # logging
  spec.add_dependency "dot-properties", ">= 0.1.1"  # reading java style .properties
  spec.add_dependency "httpclient", "~> 2.5"
  
  # If we're building the package under JRuby, add in the 
  # jruby-only gems and specify the platform.
  
  if defined? JRUBY_VERSION
    spec.platform = 'java'
    spec.add_dependency "traject-marc4j_reader", "~>1"
    spec.add_dependency "traject-solrj_writer",  "~>1"
  else
    spec.platform = "ruby"
  end
  

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest"
end
