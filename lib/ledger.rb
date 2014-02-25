require 'ledger/version'
require 'crdt/tpncounter'
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
    #     :merge_history_length [Integer]: default 50 - number of recently merged transactions to keep track of
    #        (should be equal to number of actors that may act on a given ledger at the same time)
    #     :retry_count [Integer]: default 10
    #   }
    def initialize(bucket, key, options={})
      raise ArgumentError, 'Argument "bucket" must have "allow_mult" property set to true' unless bucket.allow_mult

      self.bucket = bucket
      self.key = key
      self.retry_count = options[:retry_count] || 10

      self.counter_options = {}
      self.counter_options[:actor] = options[:actor] || Thread.current["name"] || "ACTOR1"
      self.counter_options[:history_length] = options[:history_length] || 10
      self.counter_options[:merge_history_length] = options[:merge_history_length] || 50
      self.counter = Riak::CRDT::TPNCounter.new(self.counter_options)
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
      self.update!(transaction, value)
    end

    # Decrement the counter, merge and save it
    # @param [String] transaction
    # @param [Positive Integer] value
    # @see update!(transaction, value)
    # @return [Boolean]
    def debit!(transaction, value)
      self.update!(transaction, value * -1)
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
      vclock = self.refresh()


      if self.has_transaction?(transaction)
        # If the transaction already exists in the counter, no problem
        return true
      else
        # If the transaction doesn't exist, attempt to add it and save
        if value < 0
          self.counter.decrement(transaction, value * -1)
        else
          self.counter.increment(transaction, value)
        end

        unless self.save(vclock)
          # If the save wasn't successful, retry
          current_retry = self.retry_count unless current_retry
          self.update!(transaction, value, current_retry - 1)
        else
          # If the save succeeded, no problem
          return true
        end
      end
    end

    # Check if the counter has transaction
    # @param [String] transaction
    # @return [Boolean]
    def has_transaction?(transaction)
      self.counter.has_transaction?(transaction)
    end

    # Calculate the current value of the counter
    # @return [Integer]
    def value()
      self.counter.value
    end

    # Delete the counter
    # @return [Boolean]
    def delete()
      begin
        self.bucket.delete(self.key)
        return true
      rescue => e
        return false
      end
    end

    # Get the current state of the counter and merge it
    # @return [String]
    def refresh()
      obj = self.bucket.get_or_new(self.key)
      return if obj.nil?

      self.counter = Riak::CRDT::TPNCounter.new(self.counter_options)

      if obj.siblings.length > 1
        self.counter.merge_siblings(obj.siblings, self.counter_options)
      elsif !obj.raw_data.nil?
        self.counter.merge(Riak::CRDT::TPNCounter.from_json(obj.raw_data, self.counter_options))
      end

      return obj.vclock
    end

    # Save the counter with an optional vclock
    # @param [String] vclock
    # @return [Boolean]
    def save(vclock=nil)
      object = self.bucket.new(self.key)
      object.vclock = vclock if vclock
      object.content_type = 'application/json'
      object.raw_data = self.to_json()

      begin
        options = {:returnbody => false}
        object.store(options)
        return true
      rescue => e
        return false
      end
    end

    def to_json()
      self.counter.to_json
    end
  end
end
