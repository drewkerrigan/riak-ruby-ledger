require_relative '../../test_helper'

describe Riak::CRDT::TGCounter do
  options1 = {:actor => "ACTOR1", :history_length => 5}
  options2 = {:actor => "ACTOR2", :history_length => 5}

  it "must have empty counts on new" do
    counter = Riak::CRDT::TGCounter.new(options1)
    assert_equal(0, counter.counts["ACTOR1"]["total"])
    assert_equal([], counter.counts["ACTOR1"]["requests"])
  end

  it "must increment" do
    counter = Riak::CRDT::TGCounter.new(options1)
    counter.increment("req1", 10)

    assert_equal(10, counter.counts["ACTOR1"]["total"])
    assert_equal(["req1"], counter.counts["ACTOR1"]["requests"])
  end

  it "must have value" do
    counter = Riak::CRDT::TGCounter.new(options1)
    counter.increment("req1", 10)
    counter.increment("req2", 10)

    assert_equal(20, counter.value)
  end

  it "must be idempotent before merge" do
    counter = Riak::CRDT::TGCounter.new(options1)
    counter.increment("req1", 10)
    counter.increment("req2", 10)
    counter.increment("req1", 10)
    counter.increment("req1", 10)
    counter.increment("req1", 10)

    assert_equal(20, counter.value)
  end

  it "must have an added request_id" do
    counter = Riak::CRDT::TGCounter.new(options1)
    counter.increment("req1", 10)
    counter.increment("req2", 10)

    assert counter.has_request_id? "req1"
    refute counter.has_request_id? "req3"
  end

  it "must translate to and from json" do
    json = "{\"type\":\"TGCounter\",\"c\":{\"ACTOR1\":{\"total\":20,\"requests\":[\"req1\",\"req2\"]}}}"
    counter = Riak::CRDT::TGCounter.new(options1)
    counter.increment("req1", 10)
    counter.increment("req2", 10)

    c2 = counter.clone

    assert_equal json, counter.to_json

    assert_equal c2.counts, Riak::CRDT::TGCounter.from_json(json, options1).counts
  end

  it "must merge" do
    counter = Riak::CRDT::TGCounter.new(options1)
    counter.increment("req1", 10)
    counter.increment("req2", 10) # 20
    counter.increment("req1", 10) # 20
    counter.increment("req1", 10) # 20
    counter.increment("req3", 10) # 30

    counter.increment("req4", 10) # 40
    counter.increment("req5", 10) # 50
    counter.increment("req6", 10) # 60
    counter.increment("req7", 10) # 70
    counter.increment("req8", 10) # 80



    counter2 = Riak::CRDT::TGCounter.new(options2)
    counter2.merge(counter)
    counter2.increment("req1", 10) # 80 // 0
    counter2.increment("req2", 10) # 80 // 0
    counter2.increment("req3", 10) # 80 // 0
    counter2.increment("req1", 10) # 80 // 0
    counter2.increment("req1", 10) # 80 // 0

    counter2.increment("req9", 10) # 90 // 10
    counter2.increment("req10", 10) # 100 // 20
    counter2.increment("req11", 10) # 110 // 30
    counter2.increment("req12", 10) # 120 // 40
    counter2.increment("req13", 10) # 130 // 50

    counter.merge(counter2)

    assert_equal(80, counter.counts["ACTOR1"]["total"])
    assert_equal(130, counter.value)

    counter2.merge(counter)

    assert_equal(50, counter2.counts["ACTOR2"]["total"])
    assert_equal(130, counter2.value)
  end
end