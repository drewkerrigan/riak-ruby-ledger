require 'ledger/version'
require 'tpncounter'
require 'json'

module Riak
  class Ledger
    attr_accessor :bucket, :key, :counter, :retry_count, :counter_options

    # Create a new Ledger object
    # @param [Riak::Bucket] bucket
    # @param [String] key
    # @param [Hash] options
    #   {
    #     :actor [String]: default Thread.current["name"] || "ACTOR1"
    #     :history_length [Integer]: default 10
    #     :retry_count [Integer]: default 10
    #   }
    def initialize(bucket, key, options={})
      self.bucket = bucket
      self.key = key
      self.retry_count = options[:retry_count] || 10

      self.counter_options = {}
      self.counter_options[:actor] = options[:actor] || Thread.current["name"] || "ACTOR1"
      self.counter_options[:history_length] = options[:history_length] || 10
      self.counter = Riak::CRDT::TPNCounter.new(self.counter_options)

      unless bucket.allow_mult
        bucket.allow_mult = true
      end
    end

    # Find an existing Ledger object, merge and save it
    # @param [Riak::Bucket] bucket
    # @param [String] key
    # @param [Hash] options
    #   {
    #     :actor [String]: default Thread.current["name"] || "ACTOR1"
    #     :history_length [Integer]: default 10
    #     :retry_count [Integer]: default 10
    #   }
    # @return [Riak::Ledger]
    def self.find!(bucket, key, options={})
      candidate = new(bucket, key, options)
      vclock = candidate.refresh()
      candidate.save(vclock)

      return candidate
    end

    # Increment the counter, merge and save it
    # @param [String] transaction
    # @param [Positive Integer] value
    # @see update!(transaction, value)
    # @return [Boolean]
    def credit!(transaction, value)
      update!(transaction, value)
    end

    # Decrement the counter, merge and save it
    # @param [String] transaction
    # @param [Positive Integer] value
    # @see update!(transaction, value)
    # @return [Boolean]
    def debit!(transaction, value)
      update!(transaction, value * -1)
    end

    # Update the counter, merge and save it. Retry if unsuccessful
    # @param [String] transaction
    # @param [Integer] value
    # @param [Integer] current_retry
    # @return [Boolean]
    def update!(transaction, value, current_retry=nil)
      # Failure case, not able to successfully complete the operation, retry a.s.a.p.
      if current_retry && current_retry <= 0
        return false
      end

      # Get the current merged state of this counter
      vclock = refresh()


      if has_transaction?(transaction)
        # If the transaction already exists in the counter, no problem
        return true
      else
        # If the transaction doesn't exist, attempt to add it and save
        if value < 0
          counter.decrement(transaction, value * -1)
        else
          counter.increment(transaction, value)
        end

        unless save(vclock)
          # If the save wasn't successful, retry
          current_retry = retry_count unless current_retry
          update!(transaction, value, current_retry - 1)
        else
          # If the save succeeded, no problem
          return true
        end
      end
    end

    # Create a new Ledger object
    # @param [String] transaction
    # @return [Boolean]
    def has_transaction?(transaction)
      counter.has_transaction?(transaction)
    end

    # Calculate the current value of the counter
    # @return [Integer]
    def value()
      counter.value
    end

    # Delete the counter
    # @return [Boolean]
    def delete()
      begin
        bucket.delete(key)
        return true
      rescue => e
        return false
      end
    end

    # Get the current state of the counter and merge it
    # @return [String]
    def refresh()
      obj = bucket.get_or_new(key)
      return if obj.nil?

      counter = Riak::CRDT::TPNCounter.new(self.counter_options)

      if obj.siblings.length > 1
        obj.siblings.each do | sibling |
          unless sibling.raw_data.nil? or sibling.raw_data.empty?
            counter.merge(Riak::CRDT::TPNCounter.from_json(sibling.raw_data, self.counter_options))
          end
        end
      elsif !obj.raw_data.nil?
        counter.merge(Riak::CRDT::TPNCounter.from_json(obj.raw_data, self.counter_options))
      end

      return obj.vclock
    end

    # Save the counter with an optional vclock
    # @param [String] vclock
    # @return [Boolean]
    def save(vclock=nil)
      object = bucket.new(key)
      object.vclock = vclock if vclock
      object.content_type = 'application/json'
      object.raw_data = to_json

      begin
        options = {:returnbody => false}
        object.store(options)
        return true
      rescue => e
        return false
      end
    end

    def to_json()
      counter.to_json
    end
  end
end
