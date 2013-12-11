require "ledger/version"

module Riak::Ledger
  attr_accessor :actor, :client, :bucket, :key, :counter

  def initialize(actor, client, bucket, key)
    self.actor = actor
    self.client = client
    self.bucket = bucket
    self.key = key
    self.counter = TPNCounter.new()
  end

  def self.find(actor, client, bucket, key)
    obj = client[bucket].get_or_new(key)
    return if obj.nil?

    candidate = new(actor, client, bucket, key)

    if obj.siblings.length > 1
      index_obj.siblings.each do | o |
        unless o.raw_data.nil? or o.raw_data.empty?
          candidate.counter.merge(actor, TPNCounter.from_json(o.raw_data))
        end
      end

      resolved_obj = client[bucket].new(key)
      resolved_obj.vclock = obj.vclock

      # previous content type was mulitpart/mixed, needs to change
      resolved_obj.content_type = 'application/json'
      resolved_obj.raw_data = candidate.counter.to_json
      resolved_obj.store(options={:returnbody => false})
    elsif !obj.raw_data.nil?
      candidate.counter.merge(actor, TPNCounter.from_json(obj.raw_data)))
    end
  end

  def value
    counter.value
  end

  def increment(transaction, value)
    counter.increment(actor, transaction, value)
  end

  def save()
    object = self.bucket.new(key)
    object.content_type = 'application/json'
    object.raw_data = counter.to_json

    object.store(options={:returnbody => false})
  end
end
