require 'crdt/tgcounter'

module Riak::CRDT
  class TPNCounter
    attr_accessor :p, :n

    # Create a new Request_id PNCounter
    # @param [Hash] options
    #   {
    #     :actor [String]
    #     :history_length [Integer]
    #   }
    def initialize(options)
      self.p = TGCounter.new(options)
      self.n = TGCounter.new(options)
    end

    def to_json
      {
          type: 'TPNCounter',
          p: self.p.to_hash,
          n: self.n.to_hash
      }.to_json
    end

    def self.from_json(json, options)
      h = JSON.parse json
      raise ArgumentError.new 'unexpected type field in JSON' unless h['type'] == 'TPNCounter'

      pnc = new(options)
      pnc.p = TGCounter.from_hash(h['p'], options)
      pnc.n = TGCounter.from_hash(h['n'], options)

      return pnc
    end

    # Increment this actor's positive request_id array, overwriting if the value exists
    # @param [String] request_id
    # @param [Integer] value
    def increment(request_id, value)
      self.p.increment(request_id, value)
    end

    # Increment this actor's negative request_id array, overwriting if the value exists
    # @param [String] request_id
    # @param [Integer] value
    def decrement(request_id, value)
      self.n.increment(request_id, value)
    end

    def value
      self.p.value - self.n.value
    end

    def has_request_id?(request_id)
      self.p.has_request_id?(request_id) || self.n.has_request_id?(request_id)
    end

    def merge(other)
      self.p.merge(other.p)
      self.n.merge(other.n)
    end

    def merge_siblings(siblings, counter_options)
      siblings.each do | sibling |
        unless sibling.raw_data.nil? or sibling.raw_data.empty?
          self.merge(Riak::CRDT::TPNCounter.from_json(sibling.raw_data, counter_options))
        end
      end
    end

  end
end
