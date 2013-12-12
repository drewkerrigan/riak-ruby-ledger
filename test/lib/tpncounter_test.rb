require_relative '../test_helper'

describe Riak::CRDT::TPNCounter do

  it "must have empty counts on new" do
    assert_equal({}, Riak::CRDT::TPNCounter.new().p.counts)
    assert_equal({}, Riak::CRDT::TPNCounter.new().n.counts)
  end

  it "must increment and decrement" do
    counter = Riak::CRDT::TPNCounter.new()
    counter.increment("actor1", "txn1", 10)
    assert_equal(10, counter.value)

    counter.decrement("actor1", "txn1", 10)
    assert_equal(0, counter.value)
  end


  it "must be idempotent before merge" do
    counter = Riak::CRDT::TPNCounter.new()
    counter.increment("actor1", "txn1", 10)
    counter.increment("actor2", "txn2", 10)
    counter.increment("actor3", "txn1", 10)
    counter.increment("actor3", "txn1", 10)
    counter.increment("actor3", "txn1", 10)
    counter.decrement("actor4", "txn3", 10)

    assert_equal(10, counter.value)
  end

  it "must have an added transaction" do
    counter = Riak::CRDT::TPNCounter.new()
    counter.increment("actor1", "txn1", 10)
    counter.increment("actor2", "txn2", 10)
    counter.decrement("actor3", "txn4", 10)

    assert counter.has_transaction? "txn1"
    refute counter.has_transaction? "txn3"
    assert counter.has_transaction? "txn4"
  end

  it "must translate to and from json" do
    json = "{\"type\":\"TPNCounter\",\"p\":{\"actor1\":{\"txn1\":10}},\"n\":{\"actor2\":{\"txn2\":5}}}"
    counter = Riak::CRDT::TPNCounter.new()
    counter.increment("actor1", "txn1", 10)
    counter.decrement("actor2", "txn2", 5)

    c2 = counter.clone

    assert_equal json, counter.to_json

    assert_equal c2.p.counts, Riak::CRDT::TPNCounter.from_json(json).p.counts
    assert_equal c2.n.counts, Riak::CRDT::TPNCounter.from_json(json).n.counts
  end

  it "must merge" do
    counter = Riak::CRDT::TPNCounter.new()
    counter.increment("actor1", "txn1", 10)
    counter.increment("actor2", "txn2", 10)
    counter.increment("actor3", "txn1", 10)
    counter.increment("actor3", "txn1", 10)
    counter.decrement("actor3", "txn3", 5)

    counter2 = Riak::CRDT::TPNCounter.new()
    counter2.increment("actor5", "txn1", 10)
    counter2.increment("actor2", "txn2", 10)
    counter2.increment("actor1", "txn4", 10)
    counter2.increment("actor3", "txn1", 10)
    counter2.decrement("actor6", "txn5", 1)

    counter.merge("actor1", counter2)

    assert_equal(20, counter.p.counts["actor1"]["total"])
    assert_equal(0, counter.n.counts["actor1"]["total"])

    counter.merge("actor2", counter2)

    assert_equal(10, counter.p.counts["actor2"]["total"])
    assert_equal(0, counter.n.counts["actor2"]["total"])

    counter.merge("actor3", counter2)

    assert_equal(10, counter.p.counts["actor3"]["total"])
    assert_equal(5, counter.n.counts["actor3"]["total"])

    assert_equal(nil, counter.p.counts["actor4"])
    assert_equal(nil, counter.n.counts["actor4"])

    assert_equal(10, counter.value)
  end
end