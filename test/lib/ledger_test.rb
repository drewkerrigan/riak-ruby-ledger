require_relative '../test_helper'
require 'riak'

describe Riak::Ledger do

  before do
    @client = Riak::Client.new pb_port: 8087
    @bucket = "ledger_test"
    @key = "player_1"
    @actor1 = "ACTOR1"
    @actor2 = "ACTOR2"

    @ledger1 = Riak::Ledger.new(@client, @bucket, @key, @actor1)
    @ledger2 = Riak::Ledger.new(@client, @bucket, @key, @actor2)
  end

  after do
    @ledger1.delete()
    @ledger2.delete()
  end

  it "have a valid starting state" do
    assert_equal({}, @ledger1.counter.p.counts)
    assert_equal({}, @ledger1.counter.n.counts)
  end

  it "must credit and debit" do
    @ledger1.credit("txn1", 10)
    @ledger1.credit("txn1", 10)
    @ledger1.credit("txn1", 10)

    assert_equal 10, @ledger1.value

    @ledger1.debit("txn2", 5)
    @ledger1.debit("txn2", 5)
    @ledger1.debit("txn2", 5)

    assert_equal 5, @ledger1.value
  end

  it "must have transaction" do
    @ledger1.credit("txn1", 10)
    @ledger1.debit("txn2", 5)

    assert @ledger1.has_transaction? "txn1"
    assert @ledger1.has_transaction? "txn2"
    refute @ledger1.has_transaction? "txn3"
  end

  it "must save and finds with merge" do
    @ledger1.credit("txn1", 10)
    @ledger1.save
    @ledger1.debit("txn2", 5)
    @ledger1.save
    @ledger2.credit("txn1", 10) #ignore
    @ledger2.save
    @ledger2.debit("txn2", 5) #ignore
    @ledger2.save
    @ledger2.debit("txn3", 1)
    @ledger2.save
    @ledger2.credit("txn5", 100)
    @ledger2.save

    l0 = Riak::Ledger.find(@client, @bucket, @key)

    puts YAML::dump l0.counter

    l1 = Riak::Ledger.find!(@client, @bucket, @key, @actor1)

    puts YAML::dump l1.counter

    l2 = Riak::Ledger.find!(@client, @bucket, @key, @actor2)

    puts YAML::dump l2.counter

    assert_equal 104, l1.value
    assert_equal 104, l2.value

    assert l1.has_transaction? "txn1"
    assert l1.has_transaction? "txn2"
    assert l1.has_transaction? "txn5"
    refute l1.has_transaction? "txn4"
  end

  it "must save and finds without merge" do
    @ledger1.credit("txn1", 10)
    @ledger1.save
    @ledger1.debit("txn2", 5)
    @ledger1.save
    @ledger2.credit("txn1", 10) #ignore
    @ledger2.save
    @ledger2.debit("txn2", 5) #ignore
    @ledger2.save
    @ledger2.debit("txn3", 1)
    @ledger2.save
    @ledger2.credit("txn5", 100)
    @ledger2.save

    l1 = Riak::Ledger.find(@client, @bucket, @key)

    assert_equal 104, l1.value
    assert l1.has_transaction? "txn1"
    assert l1.has_transaction? "txn2"
    assert l1.has_transaction? "txn5"
    refute l1.has_transaction? "txn4"


  end


  #
  #def self.find(client, bucket, key, actor = nil)
  #  obj = client[bucket].get_or_new(key)
  #  return if obj.nil?
  #
  #  candidate = new(nil, client, bucket, key)
  #
  #  if obj.siblings.length > 1
  #    index_obj.siblings.each do | o |
  #      unless o.raw_data.nil? or o.raw_data.empty?
  #        candidate.counter.merge(actor, TPNCounter.from_json(o.raw_data))
  #      end
  #    end
  #
  #  elsif !obj.raw_data.nil?
  #    candidate.counter.merge(actor, TPNCounter.from_json(obj.raw_data))
  #  end
  #
  #  return candidate
  #end
  #
  #def self.find!(client, bucket, key, actor)
  #  candidate = self.find(client, bucket, key, actor)
  #
  #  resolved_obj = client[bucket].new(key)
  #  resolved_obj.vclock = obj.vclock
  #
  #  # previous content type was mulitpart/mixed, needs to change
  #  resolved_obj.content_type = 'application/json'
  #  resolved_obj.raw_data = candidate.counter.to_json
  #  resolved_obj.store(options={:returnbody => false})
  #
  #  return candidate
  #end
  #
  ## Take a look at all transactions in actor sets
  #def to_json()
  #  counter.to_json
  #end

  #def save()
  #  object = self.bucket.new(key)
  #  object.content_type = 'application/json'
  #  object.raw_data = counter.to_json
  #
  #  object.store(options={:returnbody => false})
  #end

end