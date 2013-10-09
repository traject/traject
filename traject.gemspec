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
  spec.homepage      = "http://github.com/jrochkind/traject"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = ["traject"]
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.extra_rdoc_files = spec.files.grep(%r{^doc/})
end
