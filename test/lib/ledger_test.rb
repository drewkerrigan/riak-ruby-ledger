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
    assert_equal({:type=>"TGCounter", :c=>{"ACTOR1"=>{"total"=>0, "txns"=>[]}}}, @ledger1.counter.p.to_hash)
    assert_equal({:type=>"TGCounter", :c=>{"ACTOR1"=>{"total"=>0, "txns"=>[]}}}, @ledger1.counter.n.to_hash)
  end

  it "must credit and debit" do
    @ledger1.credit!("txn1", 10)
    @ledger1.credit!("txn1", 10)
    @ledger1.credit!("txn1", 10)

    assert_equal 10, @ledger1.value

    @ledger1.debit!("txn2", 5)
    @ledger1.debit!("txn2", 5)
    @ledger1.debit!("txn2", 5)

    assert_equal 5, @ledger1.value
  end

  it "must have transaction" do
    @ledger1.credit!("txn1", 10)
    @ledger1.debit!("txn2", 5)

    assert @ledger1.has_transaction? "txn1"
    assert @ledger1.has_transaction? "txn2"
    refute @ledger1.has_transaction? "txn3"
  end

  it "must save and find counters" do
    @ledger1.credit!("txn1", 10)
    @ledger1.debit!("txn2", 5)
    @ledger2.credit!("txn1", 10) #ignore
    @ledger2.debit!("txn2", 5) #ignore
    @ledger2.debit!("txn3", 1)
    @ledger2.credit!("txn5", 100)

    l1 = Riak::Ledger.find!(@bucket, @key, options1)

    l2 = Riak::Ledger.find!(@bucket, @key, options2)

    assert_equal 104, l1.value
    assert_equal 104, l2.value

    assert l1.has_transaction? "txn1"
    assert l1.has_transaction? "txn2"
    assert l1.has_transaction? "txn5"
    refute l1.has_transaction? "txn4"
  end

  it "must merge a single actor" do
    @ledger1.credit!("txn1", 10)
    @ledger1.credit!("txn2", 10)
    @ledger1.credit!("txn3", 10)
    @ledger1.credit!("txn4", 10)
    @ledger1.credit!("txn5", 10)
    @ledger1.credit!("txn6", 10)
    @ledger1.credit!("txn7", 10)
    @ledger1.credit!("txn8", 10)
    @ledger1.credit!("txn9", 10)
    @ledger1.credit!("txn10", 10)

    @ledger1.credit!("txn11", 10)
    @ledger1.credit!("txn11", 10)
    @ledger1.credit!("txn11", 10)
    @ledger1.credit!("txn11", 10)

    assert_equal 110, @ledger1.value
    #1st 5 transactions were merged into total
    assert_equal 60, @ledger1.counter.p.counts["ACTOR1"]["total"]

    refute @ledger1.has_transaction? "txn1"
    refute @ledger1.has_transaction? "txn2"
    refute @ledger1.has_transaction? "txn3"
    refute @ledger1.has_transaction? "txn4"
    refute @ledger1.has_transaction? "txn5"
    refute @ledger1.has_transaction? "txn6"
    assert @ledger1.has_transaction? "txn7"
    assert @ledger1.has_transaction? "txn8"
    assert @ledger1.has_transaction? "txn9"
    assert @ledger1.has_transaction? "txn10"
    assert @ledger1.has_transaction? "txn11"
  end

  it "must merge two actors" do
    @ledger1.debit!("txn1", 10) #-10
    @ledger1.credit!("txn2", 10) #0 p1
    @ledger1.credit!("txn3", 10) #10 p2
    @ledger1.credit!("txn4", 10) #20 p3
    @ledger1.credit!("txn5", 10) #30 p4
    @ledger2.debit!("txn6", 10) #20
    @ledger2.credit!("txn7", 10) #30 p1
    @ledger2.credit!("txn8", 10) #40 p2
    @ledger2.credit!("txn9", 10) #50 p3
    @ledger2.credit!("txn10", 10) #60 p4

    @ledger1.credit!("txn11", 10) #70 p5
    @ledger1.credit!("txn11", 10) #70 #ignore
    @ledger2.credit!("txn11", 10) #70 #ignore
    @ledger2.credit!("txn11", 10) #70 #ignore

    @ledger2.credit!("txn12", 10) #80 p5
    @ledger2.credit!("txn13", 10) #90 p6
    @ledger2.credit!("txn14", 10) #100 p7

    assert_equal 70, @ledger1.value #premerge
    @ledger1 = Riak::Ledger.find!(@bucket, @key, options1)
    assert_equal 100, @ledger1.value #postmerge

    assert_equal 100, @ledger2.value

    #1st 6 transactions were merged into total
    assert_equal 10, @ledger2.counter.p.counts["ACTOR2"]["total"] #merged 1
    @ledger2 = Riak::Ledger.find!(@bucket, @key, options2)
    assert_equal 20, @ledger2.counter.p.counts["ACTOR2"]["total"] #merged 2

    #pickup 2's merges
    @ledger1 = Riak::Ledger.find!(@bucket, @key, options1)

    assert_equal true, (@ledger1.has_transaction? "txn1")
    assert_equal true, (@ledger1.has_transaction? "txn2")
    assert_equal true, (@ledger1.has_transaction? "txn3")
    assert_equal true, (@ledger1.has_transaction? "txn4")
    assert_equal true, (@ledger1.has_transaction? "txn5")
    assert_equal true, (@ledger1.has_transaction? "txn6")
    assert_equal false, (@ledger1.has_transaction? "txn7")
    assert_equal false, (@ledger1.has_transaction? "txn8")
    assert_equal true, (@ledger1.has_transaction? "txn9")
    assert_equal true, (@ledger1.has_transaction? "txn10")
    assert_equal true, (@ledger1.has_transaction? "txn11")
  end

end