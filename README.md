# Riak-Ruby-Ledger

A PNCounter CRDT with ledger transaction ids for write idempotence

## Problem Statement

### When to use Riak Counters

Riak Counters are very well suited for certain problems:

* Facebook likes
* Youtube views
* Reddit upvotes
* Twitter followers
* Any non-critical counts
    * Counts that do not adversely affect applications or users when off by a few

### When not to use Riak Counters

* Currency (virtual or real) balances
* Metrics that result in charging a customer
    * Keeping track of how many calls are made to a paid API endpoint
    * Storage used by a user
* Real-time counts
* Any critical counts
    * Counts that must be accurate

### Counter Drift

Riak Counters as currently implemented are not ***idempotent***. This simply means that you cannot retry the same increment or decrement operation more than once.

Take the following scenario into consideration:

1. User buys an in-game item that costs 50 gold, and has a current balance of 100 gold
2. Application server attempts to debit user's account 50 gold
    a. If Riak successfully returns 200 response code, no problem!
    b. If Riak returns 500 (or any other error code), we don't have any way of knowing whether or not the operation succeeded
    c. If the application server fails at any point in the execution, we also don't have a good way of knowing whether or not the operation succeeded

In the case of 2b and 2c, we have the following choices:

* Retry the operation (Risk absolute positive drift)
    * If the original counter decrement was successful, we have now debited the user's balance twice, thereby charging them 100 gold for a 50 gold item
* Never retry (Risk absolute negative drift)
    * If the original counter decrement was unsuccessful, we gave the user an item for free

## Idempotent Counters

There are several approaches to making counters idempotent, the ones relative to this gem are described here.

### Definitions

* ***Transaction id***: Globally unique externally generated transaction id is available per counter action (increment or decrement)
* ***Actor***: A thread, process, or server that is able to serially perform actions (a single actor id can never perform actions in parallel with itself)
* ***Sibling***: In Riak, when you write to the same key without specifying a vector clock, a sibling is created. This is denoted below as `[...sibling1..., ...sibling2...]`.

### Approach 1: Ensure idempotent counter actions at any time, by any actor

This is possible if the entire transaction history is stored inside of the counter object:

Actor 1 writes txn1: 50

```
{"txn1": 50}
```

Actor 2 writes txn1: 50, txn2: 100

```
[
	#sibling 1
	{"txn1": 50},
	#sibling 2
	{"txn1": 50, "txn2": 100}
]
```

Actor 1 reads and merges value

```
{"txn1": 50, "txn2": 100}
```

Total: 150

This is not a counter, but a ***GSet***, because the entire set of transactions needs to be stored with the object. The total for a counter is defined by the sum of the entire set of values

***Pros***: 

* Retry any action at any time by any actor in the system.
* Optimize for writes: No need to read the value prior to writing a new transaction.

***Cons***: 

* GSet sizes can become too large for ruby to handle. If more than ~1000 transactions are expected for a single counter, this approach should not be used


### Approach 2a: Ensure idempotent counter actions by any actor, for the current transaction

In this approach, the transaction id is stored per actor for the most recently written transaction

Actor 1 writes txn1: 50

```
Actor1: {"total": 0} {"txn1": 50}
```

Actor 2 attempts to write txn1: 50

Actor 2 reads current value and sees that txn1 has already been written, ignores it's own txn1

Actor 2 writes merged value

```
Actor1: {"total": 0} {"txn1": 50}
```

Actor 2 Writes txn2: 100

```
Actor1: {"total": 0} {"txn1": 50}
Actor2: {"total": 0} {"txn2": 100}
```

Actor 2 Reads current value, and writes txn3: 10 along with it's own merged data

```
Actor1: {"total": 0} {"txn1": 50}
Actor2: {"total": 100} {"txn3": 10}
```

Actor 1 reads and merges value

```
Actor1: {"total": 0} {"txn1": 50}
Actor2: {"total": 100} {"txn3": 10}
```

Total: 160

***Pros***: 

* Retry an action with any actor in the system, assuming the actions are serialized per counter
* Optimize for reads: Since a very small amount of data is stored in the counter, reads should be very fast

***Cons***: 

* Counter drift is a possibility in the case where transaction 1 fails, several other transactions succeed without retrying transaction 1, and then transaction 1 is tried again

### Approach 2b: Ensure idempotent counter actions by any actor, for the previous `X` transactions

This approach is the same as 2a, but instead of only storing the most previous transaction, we store the most previous `X` transactions. In this example we'll use X=5

Actor 1 writes txn1: 50, txn2: 10, txn3: 100 (order is preserved in set)

```
Actor1: {"total": 0} {"txn1": 50, "txn2": 10, "txn3": 100}
```

Actor 2 attempts to write txn1: 50

Actor 2 reads current value and sees that txn1 has already been written, ignores it's own txn1

Actor 2 writes merged value

```
Actor1: {"total": 0} {"txn1": 50, "txn2": 10, "txn3": 100}
```

Actor 2 Writes txn4: 100

```
Actor1: {"total": 0} {"txn1": 50, "txn2": 10, "txn3": 100}
Actor2: {"total": 0} {"txn4": 100}
```

Actor 1 Writes txn5: 20, txn6: 20

```
Actor1: {"total": 0} {"txn1": 50, "txn2": 10, "txn3": 100, "txn5": 20, "txn6": 20}
Actor2: {"total": 0} {"txn4": 100}
```

Actor 1 Writes txn7: 30, and writes it's own merged data

```
Actor1: {"total": 50} {"txn2": 10, "txn3": 100, "txn5": 20, "txn6": 20, "txn7": 30}
Actor2: {"total": 0} {"txn4": 100}
```

Actor 1 reads and merges value

```
Actor1: {"total": 50} {"txn2": 10, "txn3": 100, "txn5": 20, "txn6": 20, "txn7": 30}
Actor2: {"total": 0} {"txn4": 100}
```

Total: 330

***Pros***: 

* Retry an action with any actor in the system, for the last X actions
* Optimize for reads: Since a very small amount of data is stored in the counter, reads should be very fast

***Cons***: 

* Counter drift is a possibility in the case where transaction 1 fails, X + 1 actions occur, and transaction 1 is retried

### Approach 3: Ensure idempotent counter actions by a single actor, for the current transaction

In this approach, a globally unique transaction id is no longer required, because we are assuming that only a single actor can ever be responsible for a single transaction

Actor 1 writes request1: 50, the request shows an error, but the write actually occurred in Riak

```
Actor1: {"total": 0} {"request1": 50}
```

Actor 1 retries request1: 50, the request succeeds, but since request1 is already there, it is ignored and returns a success to the client

```
Actor1: {"total": 0} {"request1": 50}
```

Actor 1 writes request2: 100, the request succeeds

```
Actor1: {"total": 50} {"request2": 100}
```

Actor 2 writes request3: 10. Since request ids are only unique to the actor, no cross-actor uniqueness check can be made.

```
Actor1: {"total": 50} {"request2": 100}
Actor2: {"total": 0} {"request3": 10}
```

Actor 2 Writes request4: 100

```
Actor1: {"total": 50} {"request2": 100}
Actor2: {"total": 10} {"request4": 100}
```

Actor 1 reads and merges value

```
Actor1: {"total": 50} {"request2": 100}
Actor2: {"total": 10} {"request4": 100}
```

Total: 260

***Pros***: 

* No reliance on an external globally unique transaction id
* Optimize for reads: Since a very small amount of data is stored in the counter, reads should be very fast

***Cons***: 

* Counter drift is a possibility if any action is retried by someone other than the current actor during it's current transaction

## Conclusion

In order to attempt to best meet the requirements of *most* counters that cannot be satisfied with Riak Counters, this gem implements approach ***2b*** as it should handle the most likely retry scenarios for most applications.


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


#Defaults:
#options = {:actor => Thread.current["name"], :history_length => 10, :retry_count => 10}
options = {}

ledger = Riak::Ledger.new(client[bucket], key, options)
```

### Credit and debit

```
ledger.credit!("transaction1", 50)
ledger.debit!("transaction2", 10)
ledger.value # 40

ledger.debit!("transaction2", 10)
ledger.value # still 40

Thread.current["name"] = "ACTOR2"

ledger = Riak::Ledger.find!(client[bucket], key)
ledger.debit!("transaction2", 10)
ledger.value # still 40

ledger.debit!("transaction3", 10)
ledger.value #now 30

Thread.current["name"] = "ACTOR1"
ledger = Riak::Ledger.find!(client[bucket], key)
ledger.value #still 40
ledger.debit!("transaction3", 10)
ledger.value #now 30
ledger.has_transaction? "transaction2" #true
ledger.has_transaction? "transaction1" #true
```

### Merging after history_length is reached

```
require 'riak'
require 'ledger'
client = Riak::Client.new pb_port: 8087
bucket = "ledgers"

options = {:history_length => 3}
key = "player_6"
ledger = Riak::Ledger.new(client[bucket], key, options)

ledger.credit!("txn1", 10)
ledger.credit!("txn2", 10)
ledger.credit!("txn3", 10)
ledger.credit!("txn4", 10)
ledger.credit!("txn5", 10)
ledger.credit!("txn6", 10)

ledger.value #60

ledger.has_transaction? "txn1" #false
ledger.has_transaction? "txn2" #false
ledger.has_transaction? "txn3" #true
ledger.has_transaction? "txn4" #true
ledger.has_transaction? "txn5" #true
ledger.has_transaction? "txn6" #true
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
