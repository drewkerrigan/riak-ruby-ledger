require 'set'

module Riak::CRDT
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

      counts.values.each do |actor|
        actor.each do |t,v|
          if t == "total"
            txns[t] = 0 unless txns[t]
            txns[t] += v
          else
            txns[t] = v
          end

        end
      end

      txns
    end

    def has_transaction?(transaction)
      transactions().keys.member?(transaction)
    end

    # Cannot modify other actors' sets because of possible simultaneous merges
    def merge(actor, other)
      merge_actor(actor, other) if actor

      other.counts.each do |act, v|
        v.each do |t, num|
          counts[act] = Hash.new() unless counts[act]
          counts[act][t] = 0 unless counts[act][t]
          other.counts[act][t] = 0 unless other.counts[act][t]

          counts[act][t] = [counts[act][t], num].max
        end
      end
    end

    def merge_actor(actor, other)
      new_keys = Set.new

      counts[actor] = Hash.new unless counts[actor]
      other.counts[actor] = Hash.new unless other.counts[actor]

      new_keys.merge counts[actor].keys
      new_keys.merge other.counts[actor].keys if other.counts[actor]

      new_keys.each do |k|
        counts[actor][k] = 0 unless counts[actor][k]
        other.counts[actor][k] = 0 unless other.counts[actor][k]

        counts[actor][k] = [counts[actor][k], other.counts[actor][k]].max
      end

      actor_total = counts[actor].values.inject(0, &:+)

      counts[actor] = Hash.new()
      counts[actor]["total"] = actor_total
    end
  end
end