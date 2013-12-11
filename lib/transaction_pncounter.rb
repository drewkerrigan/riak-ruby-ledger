module Riak::Ledger
  class TPNCounter
    attr_accessor :p, :n
    def initialize
      self.p = TGCounter.new()
      self.n = TGCounter.new()
    end

    def to_json
      {
          type: 'TPNCounter',
          p: p.counts,
          n: n.counts
      }.to_json
    end

    def self.from_json(json)
      h = JSON.parse json
      raise ArgumentError.new 'unexpected type field in JSON' unless h['type'] == 'TPNCounter'

      pnc = new
      pnc.p.counts = h['p']
      pnc.n.counts = h['n']

      return pnc
    end

    def increment(actor, transaction, value)
      p.increment(actor, transaction, value)
    end

    def decrement(actor, transaction, value)
      n.increment(actor, transaction, value)
    end

    def value
      p.value - n.value
    end

    def merge(actor, other)
      p.merge(actor, other.p)
      n.merge(actor, other.n)
    end
  end
end
