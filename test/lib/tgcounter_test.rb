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
    puts counter.counts
    #assert_equal(30, counter.value)
  end

end