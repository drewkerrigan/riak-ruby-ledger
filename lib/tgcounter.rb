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
      self.counts[self.actor]["txns"] = TransactionArray.new()
    end

    def to_hash
      c = Hash.new()
      self.counts.each do |a, values|
        c[a] = Hash.new()
        c[a]["total"] = values["total"]
        c[a]["txns"] = values["txns"].arr
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
      end

      return gc
    end

    def self.from_json(json, options)
      h = JSON.parse json
      raise ArgumentError.new 'unexpected type field in JSON' unless h['type'] == 'TGCounter'

      from_hash(h, options)
    end

    def increment(transaction, value)
      self.counts[actor]["txns"][transaction] = value
    end

    def unique_transactions(ignore_actor=nil)
      txns = Hash.new()

      self.counts.each do |a, values|
        unless a == ignore_actor
          values["txns"].arr.each do |arr|
              txns[arr[0]] = arr[1]
          end
        end
      end

      txns
    end

    def has_transaction?(transaction)
      self.unique_transactions().keys.member?(transaction)
    end

    def value()
      total = self.unique_transactions().values.inject(0, &:+)

      self.counts.values.each do |a|
        total += a["total"]
      end

      total
    end

    #scrap times or something, it's hard to deal with how to keep the correct timings...

    def merge(other)
      # Combine all actors first
      other.counts.each do |other_actor, other_values|
        if self.counts[other_actor]
          # Max of totals
          mine = self.counts[other_actor]["total"]
          self.counts[other_actor]["total"] = [mine, other_values["total"]].max

          # Max of unique transactions
          other_values["txns"].arr.each do |arr|
            other_txn, other_value = arr
            mine = (self.counts[other_actor]["txns"][other_txn]) ?
                self.counts[other_actor]["txns"][other_txn] : 0
            self.counts[other_actor]["txns"][other_txn] = [mine, other_value].max
          end
        else
          self.counts[other_actor] = other_values
        end
      end


      # Remove duplicate transactions if other actors have claimed them
      self.unique_transactions(actor).keys.each do |txn|
        self.counts[actor]["txns"].delete(txn)
      end

      # Merge this actor's data based on history_length
      total = 0
      if self.counts[actor]["txns"].length > self.history_length
        to_delete = self.counts[actor]["txns"].length - self.history_length
        self.counts[actor]["txns"].arr.slice!(0..to_delete - 1).each do |arr|
          total += arr[1]
        end
      end

      self.counts[actor]["total"] += total
    end
  end
end

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