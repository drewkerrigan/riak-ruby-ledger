# Riak-Ruby-Ledger

A PNCounter CRDT with ledger transaction ids for write idempotence

## Installation

Add this line to your application's Gemfile:

    gem 'riak-ruby-ledger'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install riak-ruby-ledger

## Usage

### Initialize

```
require 'riak'
require 'riak-ruby-ledger'

# Create a client interface
client = Riak::Client.new pb_port: 8087
bucket = "ledgers"
key = "player_1"
Thread.current["name"] = "ACTOR1"

ledger = Riak::Ledger.new(client, bucket, key, Thread.current["name"])
```

### Idempotent credit and debit

```
ledger.credit("transaction1", 50)

ledger.debit("transaction2", 10)

ledger.value # 40

ledger.debit("transaction2", 10)

ledger.value # still 40

ledger.save

ledger = Ledger.find(client, bucket, key, "ACTOR2")

ledger.debit("transaction2", 10)

ledger.value # still 40
```

### Merging

```
ledger = Ledger.find!(client, bucket, key, "ACTOR1")

ledger.value #still 40

ledger.debit("transaction2", 10)

ledger.value #now 30, after merge, transaction ids are no longer present

ledger.has_transaction? "transaction2" #true
ledger.has_transaction? "transaction1" #false

ledger.save

ledger = Ledger.find!(client, bucket, key, "ACTOR1")

ledger.has_transaction? "transaction2" #false
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
