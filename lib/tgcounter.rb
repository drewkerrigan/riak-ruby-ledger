require 'set'

module Riak::CRDT
  class TGCounter
    attr_accessor :counts, :actor, :history_length

    # Create a new Transaction GCounter
    # @param [Hash] options
    #   {
    #     :actor [String]
    #     :history_length [Integer]
    #   }
    def initialize(options)
      self.actor = options[:actor]
      self.history_length = options[:history_length]
      self.counts = Hash.new()
      self.counts[self.actor] = Hash.new()
      self.counts[self.actor]["total"] = 0
      self.counts[self.actor]["txns"] = Hash.new()
    end

    def to_json
      {
          type: 'TGCounter',
          c: counts
      }.to_json
    end

    def self.from_json(json, options)
      h = JSON.parse json
      raise ArgumentError.new 'unexpected type field in JSON' unless h['type'] == 'TGCounter'

      gc = new(options)
      gc.counts = h['c']
      return gc
    end

    def increment(transaction, value)
      counts[actor]["txns"][transaction] = value
    end

    def unique_transactions(ignore_actor=nil)
      txns = Hash.new()

      counts.each do |a, values|
        unless a == ignore_actor
          values["txns"].each do |txn, val|
              txns[txn] = val
          end
        end
      end

      txns
    end

    def has_transaction?(transaction)
      unique_transactions().keys.member?(transaction)
    end

    def value()
      total = unique_transactions().values.inject(0, &:+)

      counts.values.each do |a|
        total += a["total"]
      end

      total
    end

    def merge(other)
      # Combine all actors first
      other.counts.each do |other_actor, other_values|
        if counts[other_actor]
          # Max of totals
          counts[other_actor]["total"] = [counts[other_actor]["total"], other_values["total"]].max

          # Max of unique transactions
          other_values["txns"].each do |other_txn, other_value|
            counts[other_actor]["txns"][other_txn] = 0 unless counts[other_actor]["txns"][other_txn]
            counts[other_actor]["txns"][other_txn] = [counts[other_actor]["txns"][other_txn], other_value].max
          end
        else
          counts[other_actor] = other_values
        end
      end

      # Remove duplicate transactions if other actors have claimed them
      unique_transactions(actor).keys.each do |txn|
        counts[actor]["txns"].delete(txn)
      end

      # Merge this actor's data based on history_length
      total = 0
      if counts[actor]["txns"].length >= history_length
        (counts[actor]["txns"].length - history_length).times do
          txn = counts[actor]["txns"].shift
          total += txn[1]
        end
      end
      counts[actor]["total"] = total
    end
  end
end