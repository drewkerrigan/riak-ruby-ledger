require_relative '../../test_helper'

describe Riak::CRDT::TPNCounter do
  options1 = {:actor => "ACTOR1", :history_length => 5}
  options2 = {:actor => "ACTOR2", :history_length => 5}

  it "must have empty counts on new" do
    assert_equal({:type=>"TGCounter", :c=>{"ACTOR1"=>{"total"=>0, "requests"=>[]}}}, Riak::CRDT::TPNCounter.new(options1).p.to_hash)
    assert_equal({:type=>"TGCounter", :c=>{"ACTOR1"=>{"total"=>0, "requests"=>[]}}}, Riak::CRDT::TPNCounter.new(options1).n.to_hash)
  end

  it "must increment and decrement" do
    counter = Riak::CRDT::TPNCounter.new(options1)
    counter.increment("req1", 10)
    assert_equal(10, counter.value)

    counter.decrement("req2", 10)
    assert_equal(0, counter.value)
  end


  it "must be idempotent before merge" do
    counter = Riak::CRDT::TPNCounter.new(options1)
    counter.increment("req1", 10)
    counter.increment("req2", 10)
    counter.increment("req1", 10)
    counter.increment("req1", 10)
    counter.increment("req1", 10)
    counter.decrement("req3", 10)

    assert_equal(10, counter.value)
  end

  it "must have an added request_id" do
    counter = Riak::CRDT::TPNCounter.new(options1)
    counter.increment("req1", 10)
    counter.increment("req2", 10)
    counter.decrement("req4", 10)

    assert counter.has_request_id? "req1"
    refute counter.has_request_id? "req3"
    assert counter.has_request_id? "req4"
  end

  it "must translate to and from json" do
    json = "{\"type\":\"TPNCounter\",\"p\":{\"type\":\"TGCounter\",\"c\":{\"ACTOR1\":{\"total\":10,\"requests\":[\"req1\"]}}},\"n\":{\"type\":\"TGCounter\",\"c\":{\"ACTOR1\":{\"total\":5,\"requests\":[\"req2\"]}}}}"
    counter = Riak::CRDT::TPNCounter.new(options1)
    counter.increment("req1", 10)
    counter.decrement("req2", 5)

    c2 = counter.clone

    assert_equal json, counter.to_json

    {"type"=>"TGCounter", "c"=>{"ACTOR1"=>{"total"=>0, "requests"=>["req1"]}}}
    assert_equal c2.p.counts, Riak::CRDT::TPNCounter.from_json(json, options1).p.counts
    assert_equal c2.n.counts, Riak::CRDT::TPNCounter.from_json(json, options1).n.counts
  end

  it "must merge" do
    counter = Riak::CRDT::TPNCounter.new(options1)
    counter.increment("req1", 10) # 10
    counter.increment("req2", 10) # 20
    counter.increment("req1", 10) # 20
    counter.increment("req1", 10) # 20
    counter.decrement("req3", 5) # 15

    counter.increment("req4", 10)  # 25
    counter.increment("req5", 10) # 35
    counter.increment("req6", 10) # 45
    counter.increment("req7", 10) # 55
    counter.decrement("req8", 5) # 50

    counter2 = Riak::CRDT::TPNCounter.new(options2)
    counter2.merge(counter)
    counter2.increment("req1", 10) # 50
    counter2.increment("req2", 10) # 50
    counter2.increment("req4", 10) # 50
    counter2.increment("req1", 10) # 50
    counter2.decrement("req14", 1) # 49

    counter2.increment("req9", 10) # 59
    counter2.increment("req10", 10) # 69
    counter2.increment("req11", 10) # 79
    counter2.increment("req12", 10) # 89
    counter2.decrement("req13", 1) # 88

    counter.merge(counter2)

    assert_equal(60, counter.p.counts["ACTOR1"]["total"])
    assert_equal(88, counter.value)

    counter.increment("req9", 10) #ignore, actor 2 has it
    counter2.merge(counter)

    assert_equal(40, counter2.p.counts["ACTOR2"]["total"])
    assert_equal(88, counter2.value)
  end
end