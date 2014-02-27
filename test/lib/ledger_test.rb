require_relative '../test_helper'
require 'riak'
I18n.enforce_available_locales = false

describe Riak::Ledger do
  options1 = {:actor => "ACTOR1", :history_length => 5, :retry_count => 10}
  options2 = {:actor => "ACTOR2", :history_length => 5, :retry_count => 10}

  before do
    client = Riak::Client.new pb_port: 8087
    @bucket = client["ledger_test"]
    @bucket.allow_mult = true
    @key = "player_1"

    @ledger1 = Riak::Ledger.new(@bucket, @key, options1)
    @ledger2 = Riak::Ledger.new(@bucket, @key, options2)
  end

  after do
    @ledger1.delete()
    @ledger2.delete()
  end

  it "must raise an error if mult is not allowed" do
    @bucket.allow_mult = false

    assert_raises ArgumentError do
      Riak::Ledger.new(@bucket, @key, options1)
    end

    @bucket.allow_mult = true
  end

  it "have a valid starting state" do
    assert_equal({:type=>"TGCounter", :c=>{"ACTOR1"=>{"total"=>0, "requests"=>[]}}}, @ledger1.counter.p.to_hash)
    assert_equal({:type=>"TGCounter", :c=>{"ACTOR1"=>{"total"=>0, "requests"=>[]}}}, @ledger1.counter.n.to_hash)
  end

  it "must credit and debit" do
    @ledger1.credit!(10, "req1")
    @ledger1.credit!(10, "req1")
    @ledger1.credit!(10, "req1")

    assert_equal 10, @ledger1.value

    @ledger1.debit!(5, "req2")
    @ledger1.debit!(5, "req2")
    @ledger1.debit!(5, "req2")

    assert_equal 5, @ledger1.value
  end

  it "must have request_id" do
    @ledger1.credit!(10, "req1")
    @ledger1.debit!(5, "req2")

    assert @ledger1.has_request_id? "req1"
    assert @ledger1.has_request_id? "req2"
    refute @ledger1.has_request_id? "req3"
  end

  it "must save and find counters" do
    @ledger1.credit!(10, "req1")
    @ledger1.debit!(5, "req2")
    @ledger2.credit!(10, "req1") #ignore
    @ledger2.debit!(5, "req2") #ignore
    @ledger2.debit!(1, "req3")
    @ledger2.credit!(100, "req5")

    l1 = Riak::Ledger.find!(@bucket, @key, options1)

    l2 = Riak::Ledger.find!(@bucket, @key, options2)

    assert_equal 104, l1.value
    assert_equal 104, l2.value

    assert l1.has_request_id? "req1"
    assert l1.has_request_id? "req2"
    assert l1.has_request_id? "req5"
    refute l1.has_request_id? "req4"
  end

  it "must merge a single actor" do
    @ledger1.credit!(10, "req1")
    @ledger1.credit!(10, "req2")
    @ledger1.credit!(10, "req3")
    @ledger1.credit!(10, "req4")
    @ledger1.credit!(10, "req5")
    @ledger1.credit!(10, "req6")
    @ledger1.credit!(10, "req7")
    @ledger1.credit!(10, "req8")
    @ledger1.credit!(10, "req9")
    @ledger1.credit!(10, "req10")

    @ledger1.credit!(10, "req11")
    @ledger1.credit!(10, "req11")
    @ledger1.credit!(10, "req11")
    @ledger1.credit!(10, "req11")

    assert_equal 110, @ledger1.value
    assert_equal 110, @ledger1.counter.p.counts["ACTOR1"]["total"]

    refute @ledger1.has_request_id? "req1"
    refute @ledger1.has_request_id? "req2"
    refute @ledger1.has_request_id? "req3"
    refute @ledger1.has_request_id? "req4"
    refute @ledger1.has_request_id? "req5"
    refute @ledger1.has_request_id? "req6"
    assert @ledger1.has_request_id? "req7"
    assert @ledger1.has_request_id? "req8"
    assert @ledger1.has_request_id? "req9"
    assert @ledger1.has_request_id? "req10"
    assert @ledger1.has_request_id? "req11"
  end

  it "must merge two actors" do
    @ledger1.debit!(10, "req1")
    @ledger1.credit!(10, "req2")
    @ledger1.credit!(10, "req3")
    @ledger1.credit!(10, "req4")
    @ledger1.credit!(10, "req5")
    @ledger2.debit!(10, "req6")
    @ledger2.credit!(10, "req7")
    @ledger2.credit!(10, "req8")
    @ledger2.credit!(10, "req9")
    @ledger2.credit!(10, "req10")

    @ledger1.credit!(10, "req11")
    @ledger1.credit!(10, "req11")
    @ledger2.credit!(10, "req11")
    @ledger2.credit!(10, "req11")

    @ledger2.credit!(10, "req12")
    @ledger2.credit!(10, "req13")
    @ledger2.credit!(10, "req14")

    assert_equal 70, @ledger1.value #premerge
    @ledger1 = Riak::Ledger.find!(@bucket, @key, options1)
    assert_equal 100, @ledger1.value #postmerge

    assert_equal 100, @ledger2.value

    assert_equal 70, @ledger2.counter.p.counts["ACTOR2"]["total"]
    @ledger2 = Riak::Ledger.find!(@bucket, @key, options2)
    assert_equal 70, @ledger2.counter.p.counts["ACTOR2"]["total"]

    #pickup 2's merges
    @ledger1 = Riak::Ledger.find!(@bucket, @key, options1)

    assert_equal true, (@ledger1.has_request_id? "req1")
    assert_equal true, (@ledger1.has_request_id? "req2")
    assert_equal true, (@ledger1.has_request_id? "req3")
    assert_equal true, (@ledger1.has_request_id? "req4")
    assert_equal true, (@ledger1.has_request_id? "req5")
    assert_equal true, (@ledger1.has_request_id? "req6")
    assert_equal false, (@ledger1.has_request_id? "req7")
    assert_equal false, (@ledger1.has_request_id? "req8")
    assert_equal true, (@ledger1.has_request_id? "req9")
    assert_equal true, (@ledger1.has_request_id? "req10")
    assert_equal true, (@ledger1.has_request_id? "req11")
  end

  it "must handle concurrency" do
    ledger_options = { :actor => "result", :history_length => 10, :retry_count => 10 }
    client = Riak::Client.new pb_port: 8087
    bucket  = 'concurrency_ledger_test'
    concurrency_bucket = client[bucket]
    concurrency_bucket.allow_mult = true if !concurrency_bucket.allow_mult
    key     = concurrency_bucket.get_or_new("concurrency_player_1").key
    Riak::Ledger.new(concurrency_bucket, key, ledger_options).delete

    #recreate key to avoid I18n exception
    key = concurrency_bucket.get_or_new("concurrency_player_1").key

    10.times do |d|
      threads = []

      # 11 actors
      0.upto(10) do |c|
        thread = Thread.new(concurrency_bucket, c) do |concurrency_bucket, c|
          concurrency_ledger = Riak::Ledger.new(concurrency_bucket, key, ledger_options.merge({ :actor => "actor#{c}" }))
          concurrency_ledger.credit!(10, "req#{c}.#{d}")
        end
        thread.abort_on_exception = true
        threads << thread
      end
      threads.each { |th| th.join }

      concurrency_ledger = Riak::Ledger.find!(concurrency_bucket, key, ledger_options)

      assert_equal 110, concurrency_ledger.value
      concurrency_ledger.debit!(concurrency_ledger.value, "wipe#{d}")
    end

  end

end