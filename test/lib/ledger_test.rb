require_relative '../test_helper'
require 'riak'

describe Riak::Ledger do
  options1 = {:actor => "ACTOR1", :history_length => 5, :retry_count => 10}
  options2 = {:actor => "ACTOR2", :history_length => 5, :retry_count => 10}

  before do
    client = Riak::Client.new pb_port: 8087
    @bucket = client["ledger_test"]
    @key = "player_1"


    @ledger1 = Riak::Ledger.new(@bucket, @key, options1)
    @ledger2 = Riak::Ledger.new(@bucket, @key, options2)
  end

  after do
    @ledger1.delete()
    @ledger2.delete()
  end

  it "have a valid starting state" do
    assert_equal({"ACTOR1"=>{"total"=>0, "txns"=>{}}}, @ledger1.counter.p.counts)
    assert_equal({"ACTOR1"=>{"total"=>0, "txns"=>{}}}, @ledger1.counter.n.counts)
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

  it "must save and finds with merge" do
    @ledger1.credit!("txn1", 10)
    @ledger1.debit!("txn2", 5)
    @ledger2.credit!("txn1", 10) #ignore
    @ledger2.debit!("txn2", 5) #ignore
    @ledger2.debit!("txn3", 1)
    @ledger2.credit!("txn5", 100)

    l1 = Riak::Ledger.find!(@bucket, @key, options1)

    puts YAML::dump l1.counter

    l2 = Riak::Ledger.find!(@bucket, @key, options2)

    puts YAML::dump l2.counter

    assert_equal 104, l1.value
    assert_equal 104, l2.value

    assert l1.has_transaction? "txn1"
    assert l1.has_transaction? "txn2"
    assert l1.has_transaction? "txn5"
    refute l1.has_transaction? "txn4"
  end

  it "must save and finds without merge" do
    @ledger1.credit!("txn1", 10)
    @ledger1.debit!("txn2", 5)
    @ledger2.credit!("txn1", 10) #ignore
    @ledger2.debit!("txn2", 5) #ignore
    @ledger2.debit!("txn3", 1)
    @ledger2.credit!("txn5", 100)

    l1 = Riak::Ledger.find!(@bucket, @key, options1)

    assert_equal 104, l1.value
    assert l1.has_transaction? "txn1"
    assert l1.has_transaction? "txn2"
    assert l1.has_transaction? "txn5"
    refute l1.has_transaction? "txn4"
  end

end