# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ledger/version'

Gem::Specification.new do |spec|
  spec.name          = "riak-ruby-ledger"
  spec.version       = Riak::Ledger::VERSION
  spec.authors       = ["drewkerrigan"]
  spec.email         = ["dkerrigan@basho.com"]
  spec.description   = %q{An alternative to Riak Counters with idempotent writes within a client defined window}
  spec.summary       = %q{The data type implemented is a PNCounter CRDT with an ordered array of request_ids for each GCounter actor. Request ids are stored with the GCounter, so operations against this counter are idempotent while the request_id remains in any actor's array.}
  spec.homepage      = "https://github.com/drewkerrigan/riak-ruby-ledger"
  spec.license       = "Apache2"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_dependency "json"
  spec.add_dependency "riak-client"
end
