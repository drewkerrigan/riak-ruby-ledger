require_relative '../test_helper'

describe Riak::CRDT::TGCounter do
  options1 = {:actor => "ACTOR1", :history_length => 5}
  options2 = {:actor => "ACTOR2", :history_length => 5}

  it "must have empty counts on new" do
    assert_equal({"ACTOR1"=>{"total"=>0, "txns"=>{}}}, Riak::CRDT::TGCounter.new(options1).counts)
  end

  it "must increment" do
    counter = Riak::CRDT::TGCounter.new(options1)
    counter.increment("txn1", 10)
    assert_equal({"ACTOR1"=>{"total"=>0, "txns"=>{"txn1"=>10}}}, counter.counts)
  end

  it "must have value" do
    counter = Riak::CRDT::TGCounter.new(options1)
    counter.increment("txn1", 10)
    counter.increment("txn2", 10)

    assert_equal(20, counter.value)
  end

  it "must be idempotent before merge" do
    counter = Riak::CRDT::TGCounter.new(options1)
    counter.increment("txn1", 10)
    counter.increment("txn2", 10)
    counter.increment("txn1", 10)
    counter.increment("txn1", 10)
    counter.increment("txn1", 10)

    assert_equal(20, counter.value)
  end

  it "must have an added transaction" do
    counter = Riak::CRDT::TGCounter.new(options1)
    counter.increment("txn1", 10)
    counter.increment("txn2", 10)

    assert counter.has_transaction? "txn1"
    refute counter.has_transaction? "txn3"
  end

  it "must translate to and from json" do
    json = "{\"type\":\"TGCounter\",\"c\":{\"ACTOR1\":{\"total\":0,\"txns\":{\"txn1\":10,\"txn2\":10}}}}"
    counter = Riak::CRDT::TGCounter.new(options1)
    counter.increment("txn1", 10)
    counter.increment("txn2", 10)

    c2 = counter.clone

    assert_equal json, counter.to_json

    assert_equal c2.counts, Riak::CRDT::TGCounter.from_json(json, options1).counts
  end

  it "must merge" do
    counter = Riak::CRDT::TGCounter.new(options1)
    counter.increment("txn1", 10)
    counter.increment("txn2", 10)
    counter.increment("txn1", 10)
    counter.increment("txn1", 10)
    counter.increment("txn3", 10)

    counter.increment("txn4", 10)
    counter.increment("txn5", 10)
    counter.increment("txn6", 10)
    counter.increment("txn7", 10)
    counter.increment("txn8", 10)

    counter2 = Riak::CRDT::TGCounter.new(options2)
    counter2.increment("txn1", 10)
    counter2.increment("txn2", 10)
    counter2.increment("txn3", 10)
    counter2.increment("txn1", 10)
    counter2.increment("txn1", 10)

    counter2.increment("txn9", 10)
    counter2.increment("txn10", 10)
    counter2.increment("txn11", 10)
    counter2.increment("txn12", 10)
    counter2.increment("txn13", 10)

    counter.merge(counter2)

    assert_equal(0, counter.counts["ACTOR1"]["total"])
    assert_equal(130, counter.value)

    counter2.merge(counter)

    assert_equal(30, counter2.counts["ACTOR2"]["total"])
    assert_equal(130, counter2.value)
  end
end