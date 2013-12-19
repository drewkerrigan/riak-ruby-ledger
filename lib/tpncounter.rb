require 'tgcounter'

module Riak::CRDT
  class TPNCounter
    attr_accessor :p, :n

    # Create a new Transaction PNCounter
    # @param [Hash] options
    #   {
    #     :actor [String]
    #     :history_length [Integer]
    #   }
    def initialize(options)
      self.p = TGCounter.new(options)
      self.n = TGCounter.new(options)
    end

    def to_json
      {
          type: 'TPNCounter',
          p: self.p.to_hash,
          n: self.n.to_hash
      }.to_json
    end

    def self.from_json(json, options)
      h = JSON.parse json
      raise ArgumentError.new 'unexpected type field in JSON' unless h['type'] == 'TPNCounter'

      pnc = new(options)
      pnc.p = TGCounter.from_hash(h['p'], options)
      pnc.n = TGCounter.from_hash(h['n'], options)

      return pnc
    end

    def increment(transaction, value)
      self.p.increment(transaction, value)
    end

    def decrement(transaction, value)
      self.n.increment(transaction, value)
    end

    def value
      self.p.value - self.n.value
    end

    def has_transaction?(transaction)
      self.p.has_transaction?(transaction) || self.n.has_transaction?(transaction)
    end

    def merge(other)
      self.p.merge(other.p)
      self.n.merge(other.n)
    end
  end
end
