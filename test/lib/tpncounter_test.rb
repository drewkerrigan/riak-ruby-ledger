require_relative '../test_helper'

describe Riak::CRDT::TPNCounter do
  options1 = {:actor => "ACTOR1", :history_length => 5}
  options2 = {:actor => "ACTOR2", :history_length => 5}

  it "must have empty counts on new" do
    assert_equal({:type=>"TGCounter", :c=>{"ACTOR1"=>{"total"=>0, "txns"=>[]}}}, Riak::CRDT::TPNCounter.new(options1).p.to_hash)
    assert_equal({:type=>"TGCounter", :c=>{"ACTOR1"=>{"total"=>0, "txns"=>[]}}}, Riak::CRDT::TPNCounter.new(options1).n.to_hash)
  end

  it "must increment and decrement" do
    counter = Riak::CRDT::TPNCounter.new(options1)
    counter.increment("txn1", 10)
    assert_equal(10, counter.value)

    counter.decrement("txn2", 10)
    assert_equal(0, counter.value)
  end


  it "must be idempotent before merge" do
    counter = Riak::CRDT::TPNCounter.new(options1)
    counter.increment("txn1", 10)
    counter.increment("txn2", 10)
    counter.increment("txn1", 10)
    counter.increment("txn1", 10)
    counter.increment("txn1", 10)
    counter.decrement("txn3", 10)

    assert_equal(10, counter.value)
  end

  it "must have an added transaction" do
    counter = Riak::CRDT::TPNCounter.new(options1)
    counter.increment("txn1", 10)
    counter.increment("txn2", 10)
    counter.decrement("txn4", 10)

    assert counter.has_transaction? "txn1"
    refute counter.has_transaction? "txn3"
    assert counter.has_transaction? "txn4"
  end

  it "must translate to and from json" do
    json = "{\"type\":\"TPNCounter\",\"p\":{\"type\":\"TGCounter\",\"c\":{\"ACTOR1\":{\"total\":0,\"txns\":[[\"txn1\",10]]}}},\"n\":{\"type\":\"TGCounter\",\"c\":{\"ACTOR1\":{\"total\":0,\"txns\":[[\"txn2\",5]]}}}}"
    counter = Riak::CRDT::TPNCounter.new(options1)
    counter.increment("txn1", 10)
    counter.decrement("txn2", 5)

    c2 = counter.clone

    assert_equal json, counter.to_json

    {"type"=>"TGCounter", "c"=>{"ACTOR1"=>{"total"=>0, "txns"=>[["txn1", 10]]}}}
    assert_equal c2.p.counts, Riak::CRDT::TPNCounter.from_json(json, options1).p.counts
    assert_equal c2.n.counts, Riak::CRDT::TPNCounter.from_json(json, options1).n.counts
  end

  it "must merge" do
    counter = Riak::CRDT::TPNCounter.new(options1)
    counter.increment("txn1", 10)
    counter.increment("txn2", 10)
    counter.increment("txn1", 10)
    counter.increment("txn1", 10)
    counter.decrement("txn3", 5)

    counter.increment("txn4", 10)
    counter.increment("txn5", 10)
    counter.increment("txn6", 10)
    counter.increment("txn7", 10)
    counter.decrement("txn8", 5)

    counter2 = Riak::CRDT::TPNCounter.new(options2)
    counter2.increment("txn1", 10)
    counter2.increment("txn2", 10)
    counter2.increment("txn4", 10)
    counter2.increment("txn1", 10)
    counter2.decrement("txn5", 1)

    counter2.increment("txn9", 10)
    counter2.increment("txn10", 10)
    counter2.increment("txn11", 10)
    counter2.increment("txn12", 10)
    counter2.decrement("txn13", 1)

    counter.merge(counter2)

    assert_equal(0, counter.p.counts["ACTOR1"]["total"])
    assert_equal(88, counter.value)

    counter2.merge(counter)

    assert_equal(20, counter2.p.counts["ACTOR2"]["total"])
    assert_equal(88, counter2.value)
  end
end