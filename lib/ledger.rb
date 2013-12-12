require 'ledger/version'
require 'tpncounter'

module Riak
  module Ledger
    attr_accessor :client, :bucket, :key, :actor, :counter

    def initialize(client, bucket, key, actor)
      self.actor = actor
      self.client = client
      self.bucket = bucket
      self.key = key
      self.counter = TPNCounter.new()

      if !client[bucket].allow_mult
        client[bucket].allow_mult = true
      end
    end

    def self.find(client, bucket, key, actor = nil)
      obj = client[bucket].get_or_new(key)
      return if obj.nil?

      candidate = new(nil, client, bucket, key)

      if obj.siblings.length > 1
        index_obj.siblings.each do | o |
          unless o.raw_data.nil? or o.raw_data.empty?
            candidate.counter.merge(actor, TPNCounter.from_json(o.raw_data))
          end
        end

      elsif !obj.raw_data.nil?
        candidate.counter.merge(actor, TPNCounter.from_json(obj.raw_data))
      end

      return candidate
    end

    def self.find!(client, bucket, key, actor)
      candidate = self.find(client, bucket, key, actor)

      resolved_obj = client[bucket].new(key)
      resolved_obj.vclock = obj.vclock

      # previous content type was mulitpart/mixed, needs to change
      resolved_obj.content_type = 'application/json'
      resolved_obj.raw_data = candidate.counter.to_json
      resolved_obj.store(options={:returnbody => false})

      return candidate
    end

    def has_transaction?(transaction)
      counter.has_transaction?(transaction)
    end

    # Take a look at all transactions in actor sets
    def to_json()
      counter.to_json
    end

    def value
      counter.value
    end

    def credit(transaction, value)
      counter.increment(actor, transaction, value)
    end

    def debit(transaction, value)
      counter.decrement(actor, transaction, value)
    end

    def save()
      object = self.bucket.new(key)
      object.content_type = 'application/json'
      object.raw_data = counter.to_json

      object.store(options={:returnbody => false})
    end
  end
end
