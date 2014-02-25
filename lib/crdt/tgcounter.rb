module Riak::CRDT
  class TGCounter
    attr_accessor :counts, :actor, :history_length, :merge_history_length

    # Create a new Transaction GCounter
    # @param [Hash] options
    #   {
    #     :actor [String]
    #     :history_length [Integer]
    #   }
    def initialize(options)
      self.actor = options[:actor]
      self.history_length = options[:history_length]
      self.merge_history_length = options[:merge_history_length] || 50
      self.counts = Hash.new()
      self.counts[self.actor] = Hash.new()
      self.counts[self.actor]["total"] = 0
      self.counts[self.actor]["txns"] = TransactionArray.new()
      self.counts[self.actor]["merge_history"] = []
    end

    def to_hash
      c = Hash.new()
      self.counts.each do |a, values|
        c[a] = Hash.new()
        c[a]["total"] = values["total"]
        c[a]["txns"] = values["txns"].arr
        c[a]["merge_history"] = values["merge_history"]
      end

      {
          type: 'TGCounter',
          c: c
      }
    end

    def to_json
      self.to_hash.to_json
    end

    def self.from_hash(h, options)
      gc = new(options)

      h['c'].each do |a, values|
        gc.counts[a] = Hash.new() unless gc.counts[a]
        gc.counts[a]["total"] = values["total"]
        gc.counts[a]["txns"] = TransactionArray.new(values["txns"])
        gc.counts[a]["merge_history"] = values["merge_history"]
      end

      return gc
    end

    def self.from_json(json, options)
      h = JSON.parse json
      raise ArgumentError.new 'unexpected type field in JSON' unless h['type'] == 'TGCounter'

      from_hash(h, options)
    end

    # Increment this actor's transaction array, overwriting if the value exists
    # @param [String] transaction
    # @param [Integer] value
    def increment(transaction, value)
      self.counts[actor]["txns"][transaction] = value
    end

    # Get unique list of all transactions and values across all known actors, or optionally for a single actor
    # @param [String] for_actor
    # @return [Hash]
    def unique_transactions(for_actor=nil)
      txns = Hash.new()

      self.counts.each do |a, values|
        next if for_actor && a != for_actor
        values["txns"].arr.each do |arr|
          txns[arr[0]] = arr[1]
        end
      end

      txns
    end

    # Get unique list of all duplicate transactions per actor other than self
    # @return [Hash]
    def duplicate_transactions_by_actor()
      actor_txns = Hash.new()

      my_transactions = self.unique_transactions(self.actor).keys

      self.counts.keys.each do |a|
        next if a == self.actor
        uniques = self.unique_transactions(a).keys
        actor_txns[a] = (my_transactions & uniques)
      end

      actor_txns
    end

    # Get unique list of all duplicate transactions for all actors other than self
    # @return [Hash]
    def duplicate_transactions()
      duplicates = Hash.new()

      self.duplicate_transactions_by_actor().each do |a, txns|
        txns.each do |txn, val|
          duplicates[txn] = val
        end
      end

      duplicates
    end

    def has_transaction?(transaction)
      self.unique_transactions().keys.member?(transaction)
    end

    # Sum of totals and currently tracked transactions
    # @return [Integer]
    def value()
      total = self.unique_transactions().values.inject(0, &:+)

      self.counts.values.each do |a|
        #puts a.inspect
        total += a["total"]
      end

      total
    end

    # Merge actor data from a sibling into self, additionally remove duplicate
    # transactions and compress oldest transactions that exceed the
    # :history_length param into actor's total
    # @param [TGCounter] other
    def merge(other, sibling_compression_counter = nil)
      self.merge_actors(other)
      self.remove_duplicates()
      self.compress_history(sibling_compression_counter)
    end

    def cleanup_merge_history
      # truncate merge history
      if self.counts[actor]["merge_history"].length > self.merge_history_length
        amount_to_slice = merge_history_current_length - merge_history_max_length
        self.counts[actor]["merge_history"].slice!(0..amount_to_slice - 1)
      end
    end

    def recently_merged?(actor, txn)
      self.counts[actor]["merge_history"].include?(txn)
    end

    # Combine all actors' data
    def merge_actors(other)
      other.counts.each do |other_actor, other_values|
        if self.counts[other_actor]
          # Merge in their merge history
          if self.counts[other_actor]["merge_history"] != other_values["merge_history"]
            self.counts[other_actor]["merge_history"] << other_values["merge_history"]
            self.counts[other_actor]["merge_history"].flatten!.uniq!
            self.cleanup_merge_history
          end

          # Max of totals
          mine = self.counts[other_actor]["total"]
          self.counts[other_actor]["total"] = [mine, other_values["total"]].max

          # Max of unique transactions
          other_values["txns"].arr.each do |arr|
            other_txn, other_value = arr
            if(!recently_merged?(other_actor, other_txn))
              mine = (self.counts[other_actor]["txns"][other_txn]) ?
                  self.counts[other_actor]["txns"][other_txn] : 0
              self.counts[other_actor]["txns"][other_txn] = [mine, other_value].max
            else
              self.counts[other_actor]["txns"].delete(other_txn)
            end
          end
        else
          self.counts[other_actor] = other_values
          self.counts[other_actor]["txns"].arr.each do |(txn, val)|
            self.counts[other_actor]["txns"].delete(txn) if recently_merged?(other_actor, txn)
          end
        end

        self.counts[other_actor]["txns"].arr.each do |(txn, val)|
          self.counts[other_actor]["txns"].delete(txn) if recently_merged?(other_actor, txn)
        end

      end

    end

    # Remove duplicate transactions if other actors have claimed them
    def remove_duplicates()
      self.duplicate_transactions_by_actor().each do |a, txns|
        # Spaceship operator, if my actor is of greater value than theirs, skip because they should remove the dupe
        next if (self.actor <=> a) == 1
        txns.each do |txn|
          self.counts[self.actor]["txns"].delete(txn)
        end
      end
    end

    # Compress this actor's data based on history_length
    def compress_history(compression_counter = nil)
      total = 0

      duplicates = self.duplicate_transactions()

      if self.counts[actor]["txns"].length > self.history_length
        to_delete = self.counts[actor]["txns"].length - self.history_length
        self.counts[actor]["txns"].arr.slice!(0..to_delete - 1).each do |arr|
          txn, val = arr
          if !compression_counter.nil?
            compression_counter[actor] ||= {}
            compression_counter[actor][txn] = val
          else
            total += val unless duplicates.member? txn
          end
          self.counts[actor]["merge_history"] << txn
        end
      end

      self.counts[actor]["total"] += total
    end
  end
end

# Ease of use class - Wraps an ordered array with some hash-like functions
class TransactionArray
  attr_accessor :arr

  def initialize(arr=Array.new())
    self.arr = arr
  end

  def length()
    self.arr.length
  end

  def ==(other)
    self.arr == other.arr
  end

  def []=(key, value)
    self.delete(key) if self.[](key)
    self.arr << [key, value]
  end

  def [](key)
    res = self.arr.select { |a| a[0] == key }
    res.first[1] if res && res.length > 0 &&res.first.length == 2
  end

  def delete(key)
    index = self.arr.index { |a| a[0] == key }
    self.arr.delete_at(index) if index
  end
end