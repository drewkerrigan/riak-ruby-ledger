# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ledger/version'

Gem::Specification.new do |spec|
  spec.name          = "riak-ruby-ledger"
  spec.version       = Riak::Ledger::VERSION
  spec.authors       = ["drewkerrigan"]
  spec.email         = ["dkerrigan@basho.com"]
  spec.description   = %q{A PNCounter CRDT based ledger with support for transaction ids and tunable write idempotence}
  spec.summary       = %q{This gem attempts to provide a tunable Counter option by combining non-idempotent GCounters and a partially idempotent GSet for calculating a running counter or ledger. By allowing clients to set how many transactions to keep in the counter object as well as set a retry policy on the Riak actions performed on the counter, a good balance can be achieved.}
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
