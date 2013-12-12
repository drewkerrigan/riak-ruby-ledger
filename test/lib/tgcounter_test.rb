require_relative '../test_helper'

describe Riak::Ledger do

  it "must have empty counts on new" do
    assert_equal({}, Riak::Ledger::TGCounter.new().counts)
  end

  it "must increment" do
    counter = Riak::Ledger::TGCounter.new()
    counter.increment("actor1", "txn1", 10)
    assert_equal({"actor1"=>{"txn1"=>10}}, counter.counts)
  end

  it "must have value" do
    counter = Riak::Ledger::TGCounter.new()
    counter.increment("actor1", "txn1", 10)
    counter.increment("actor2", "txn2", 10)

    assert_equal(20, counter.value)
  end

  it "must be idempotent before merge" do
    counter = Riak::Ledger::TGCounter.new()
    counter.increment("actor1", "txn1", 10)
    counter.increment("actor2", "txn2", 10)
    counter.increment("actor3", "txn1", 10)
    counter.increment("actor3", "txn1", 10)
    counter.increment("actor3", "txn1", 10)

    assert_equal(20, counter.value)
  end

  it "must have an added transaction" do
    counter = Riak::Ledger::TGCounter.new()
    counter.increment("actor1", "txn1", 10)
    counter.increment("actor2", "txn2", 10)

    assert counter.has_transaction? "txn1"
    refute counter.has_transaction? "txn3"
  end

  it "must translate to and from json" do
    json = "{\"type\":\"TGCounter\",\"c\":{\"actor1\":{\"txn1\":10},\"actor2\":{\"txn2\":10}}}"
    counter = Riak::Ledger::TGCounter.new()
    counter.increment("actor1", "txn1", 10)
    counter.increment("actor2", "txn2", 10)

    c2 = counter.clone

    assert_equal json, counter.to_json

    assert_equal c2.counts, Riak::Ledger::TGCounter.from_json(json).counts
  end

  it "must merge" do
    counter = Riak::Ledger::TGCounter.new()
    counter.increment("actor1", "txn1", 10)
    counter.increment("actor2", "txn2", 10)
    counter.increment("actor3", "txn1", 10)
    counter.increment("actor3", "txn1", 10)
    counter.increment("actor3", "txn3", 10)

    counter2 = Riak::Ledger::TGCounter.new()
    counter2.increment("actor5", "txn1", 10)
    counter2.increment("actor2", "txn2", 10)
    counter2.increment("actor1", "txn3", 10)
    counter2.increment("actor3", "txn1", 10)
    counter2.increment("actor6", "txn1", 10)

    counter.merge("actor1", counter2)

    assert_equal({}, counter.counts)
  end

end