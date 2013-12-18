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
          p: p.counts,
          n: n.counts
      }.to_json
    end

    def self.from_json(json, options)
      h = JSON.parse json
      raise ArgumentError.new 'unexpected type field in JSON' unless h['type'] == 'TPNCounter'

      pnc = new(options)
      pnc.p.counts = h['p']
      pnc.n.counts = h['n']

      return pnc
    end

    def increment(transaction, value)
      p.increment(transaction, value)
    end

    def decrement(transaction, value)
      n.increment(transaction, value)
    end

    def value
      p.value - n.value
    end

    def has_transaction?(transaction)
      p.has_transaction?(transaction) || n.has_transaction?(transaction)
    end

    def merge(other)
      p.merge(other.p)
      n.merge(other.n)
    end
  end
end
