require 'set'

module Riak::Ledger
  class TGCounter
    attr_accessor :counts

    def initialize()
      self.counts = Hash.new()
    end

    def to_json()
      {
          type: 'TGCounter',
          c: counts
      }.to_json
    end

    def self.from_json(json)
      h = JSON.parse json
      raise ArgumentError.new 'unexpected type field in JSON' unless h['type'] == 'TGCounter'

      gc = new
      gc.counts = h['c']
      return gc
    end

    def increment(actor, transaction, value)
      counts[actor] = Hash.new() unless counts[actor]
      counts[actor][transaction] = value
    end

    def value()
      transactions().values.inject(0, &:+)
    end

    def transactions()
      txns = Hash.new()

      counts.values.each do |txn|
        txn.each do |t,v|
          txns[t] = v
        end
      end

      txns
    end

    def has_transaction?(transaction)
      transactions().keys.member?(transaction)
    end

    # Cannot modify other actors' sets because of possible simultaneous merges
    def merge(actor, other)
      new_keys = Set.new
      counts[actor] = Hash.new unless counts[actor]
      new_keys.merge counts[actor].keys
      new_keys.merge other.counts[actor].keys if other.counts[actor]

      new_keys.each do |k|
        counts[actor][k] = [counts[actor][k], other.counts[actor][k]].max
      end

      actor_total = counts[actor].values.inject(0, &:+)

      counts[actor] = Hash.new()
      counts[actor]["total"] = actor_total
    end
  end
end