require 'crdt/tgcounter'

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

    # Increment this actor's positive transaction array, overwriting if the value exists
    # @param [String] transaction
    # @param [Integer] value
    def increment(transaction, value)
      self.p.increment(transaction, value)
    end

    # Increment this actor's negative transaction array, overwriting if the value exists
    # @param [String] transaction
    # @param [Integer] value
    def decrement(transaction, value)
      self.n.increment(transaction, value)
    end

    def value
      self.p.value - self.n.value
    end

    def has_transaction?(transaction)
      self.p.has_transaction?(transaction) || self.n.has_transaction?(transaction)
    end

    def merge(other, sibling_compression_counter_p = nil, sibling_compression_counter_n = nil)
      self.p.merge(other.p, sibling_compression_counter_p)
      self.n.merge(other.n, sibling_compression_counter_n)
    end

    def merge_siblings(siblings, counter_options)
      sibling_compression_counter_p = {}
      sibling_compression_counter_n = {}

      siblings.each do | sibling |
        unless sibling.raw_data.nil? or sibling.raw_data.empty?
          self.merge(Riak::CRDT::TPNCounter.from_json(sibling.raw_data, counter_options), sibling_compression_counter_p, sibling_compression_counter_n)
        end
      end

      # add the unique transactions from all siblings totals to the total counter
      sibling_compression_counter_p.each do |actor, txn_map|
        self.p.counts[actor]["total"] += txn_map.values.inject(0, &:+)
      end
      sibling_compression_counter_n.each do |actor, txn_map|
        self.n.counts[actor]["total"] += txn_map.values.inject(0, &:+)
      end
    end

  end
end
