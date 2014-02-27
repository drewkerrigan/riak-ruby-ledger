require 'ledger/version'
require 'crdt/tpncounter'
require 'json'
require 'securerandom'

module Riak
  class Ledger
    attr_accessor :bucket, :key, :counter, :retry_count, :counter_options

    # Create a new Ledger object
    # @param [Riak::Bucket] bucket
    # @param [String] key
    # @param [Hash] options
    #   {
    #     :actor [String]: default Thread.current["name"] || "ACTOR1"
    #     :retry_count [Integer]: default 10
    #     :history_length [Integer]: default 50
    #   }
    def initialize(bucket, key, options={})
      raise ArgumentError, 'Argument "bucket" must have "allow_mult" property set to true' unless bucket.allow_mult

      self.bucket = bucket
      self.key = key
      self.retry_count = options[:retry_count] || 10

      self.counter_options = {}
      self.counter_options[:actor] = options[:actor] || Thread.current["name"] || "ACTOR1"
      self.counter_options[:history_length] = options[:history_length] || 50
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
    # @param [Positive Integer] value
    # @param [String] request_id
    # @see update!(value, request_id)
    # @return [Boolean]
    def credit!(value, request_id=nil)
      self.update!(value, request_id)
    end

    # Decrement the counter, merge and save it
    # @param [Positive Integer] value
    # @param [String] request_id
    # @see update!(value, request_id)
    # @return [Boolean]
    def debit!(value, request_id=nil)
      self.update!(value * -1, request_id)
    end

    # Update the counter, merge and save it. Retry if unsuccessful
    # @param [Integer] value
    # @param [String] request_id (optional, created if not given)
    # @param [Integer] current_retry (optional / internal increment value)
    # @return [Boolean true if successful, String request_id if not]
    def update!(value, request_id=nil, current_retry=nil)
      request_id = SecureRandom.uuid unless request_id

      # Failure case, not able to successfully complete the operation, retry a.s.a.p.
      if current_retry && current_retry <= 0
        return request_id
      end

      # Get the current merged state of this counter
      vclock = self.refresh()

      if self.has_request_id?(request_id)
        # If the request_id already exists in the counter, return success
        return true
      else
        # If the request_id doesn't exist, attempt to add it and save
        if value < 0
          self.counter.decrement(request_id, value * -1)
        else
          self.counter.increment(request_id, value)
        end

        unless self.save(vclock)
          # If the save wasn't successful, retry
          current_retry = self.retry_count unless current_retry
          self.update!(value, request_id, current_retry - 1)
        else
          # If the save succeeded, no problem
          return true
        end
      end
    end

    # Check if the counter has request_id
    # @param [String] request_id
    # @return [Boolean]
    def has_request_id?(request_id)
      self.counter.has_request_id?(request_id)
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
