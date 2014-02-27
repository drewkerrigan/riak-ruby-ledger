module Riak::CRDT
  class TGCounter
    attr_accessor :counts, :actor, :history_length

    # Create a new Request_id GCounter
    # @param [Hash] options
    #   {
    #     :actor [String]
    #     :history_length [Integer]
    #   }
    def initialize(options)
      self.actor = options[:actor]
      self.history_length = options[:history_length] || 50
      self.counts = Hash.new()
      self.counts[self.actor] = Hash.new()
      self.counts[self.actor]["total"] = 0
      self.counts[self.actor]["requests"] = Array.new()
    end

    def to_hash
      c = Hash.new()
      self.counts.each do |a, values|
        c[a] = Hash.new()
        c[a]["total"] = values["total"]
        c[a]["requests"] = values["requests"]
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
        gc.counts[a]["requests"] = values["requests"]
      end

      return gc
    end

    def self.from_json(json, options)
      h = JSON.parse json
      raise ArgumentError.new 'unexpected type field in JSON' unless h['type'] == 'TGCounter'

      from_hash(h, options)
    end

    # Increment this actor's total, add request_id
    # @param [String] request_id
    # @param [Integer] value
    def increment(request_id, value)
      unless has_request_id? request_id
        self.counts[actor]["total"] += value
        self.counts[actor]["requests"] << request_id
      end
    end

    # Has any actor attempted this request?
    def has_request_id?(request_id)

      self.counts.values.each do |a|
        return true if a["requests"].member?(request_id)
      end

      return false
    end

    # Sum of totals and currently tracked request_ids
    # @return [Integer]
    def value()
      total = 0

      self.counts.values.each do |a|
        total += a["total"]
      end

      total
    end

    # Merge actor data from a sibling into self, additionally compress oldest request_ids that exceed the
    # :history_length param
    # @param [TGCounter] other
    def merge(other)
      self.merge_actors(other)
      self.compress_history()
    end

    # Combine all actors' data
    def merge_actors(other)
      other.counts.each do |other_actor, other_values|
        if self.counts[other_actor]

          # Max of totals
          mine = self.counts[other_actor]["total"]
          self.counts[other_actor]["total"] = [mine, other_values["total"]].max

          # Unique request_ids
          other_values["requests"].each do |request_id|
            self.counts[other_actor]["requests"] << request_id unless self.counts[other_actor]["requests"].member?(request_id)
          end

        else
          self.counts[other_actor] = other_values
        end
      end

    end

    # Compress this actor's data based on history_length
    def compress_history()
      if self.counts[actor]["requests"].length > self.history_length
        to_delete = self.counts[actor]["requests"].length - self.history_length
        self.counts[actor]["requests"].slice!(0..to_delete-1)
      end
    end
  end
end