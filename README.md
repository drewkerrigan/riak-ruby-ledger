# Riak-Ruby-Ledger

An alternative to Riak Counters with conditional idempotent features.

## Quick Links

Below are a few documents that are relevant to this gem, **please read before considering using this gem for anything important**.

* [[docs/riak_counters_and_drift.md]](https://github.com/drewkerrigan/riak-ruby-ledger/blob/master/docs/riak_counters_and_drift.md): Why Riak Counters may or may not work for your use case (Counter Drift).
* [[docs/idempotent_counter_approaches.md]](https://github.com/drewkerrigan/riak-ruby-ledger/blob/master/docs/idempotent_counter_approaches.md): Some other approaches to this problem including the reasoning behind this implementation.
* [[docs/implementation.md]](https://github.com/drewkerrigan/riak-ruby-ledger/blob/master/docs/implementation.md): Implementation details about this gem.
* [[docs/usage.md]](https://github.com/drewkerrigan/riak-ruby-ledger/blob/master/docs/usage.md): Suggested usage of this gem from your application, and implications of changing various settings.


## Summary

The data type implemented is a PNCounter CRDT with a fixed length GSet for each GCounter actor. Transaction ids are stored in the GSet, so operations against this counter are idempotent while the transaction remains in the set.

More details about edge cases and how they are handled can be found in the [[docs/implementation.md]](https://github.com/drewkerrigan/riak-ruby-ledger/blob/master/docs/implementation.md)



####Why not Riak Counter

### What does it do?

This gem attempts to provide a tunable Counter option by combining non-idempotent GCounters and a partially idempotent GSet for calculating a running counter or ledger.

#### Tunable Transaction History
By allowing clients to set how many transactions to keep in the counter object as well as set a retry policy on the Riak actions performed on the counter, a good balance can be achieved. The `Riak::Ledger` class in this gem can be instantiated with the following options:

```
:actor => Actor ID, one per thread or serialized writer
:history_length => Number of transactions to store per actor per type (credit or debit)
:retry_count => Number of times to retry Riak requests if they fail
```

Furthermore, each `#credit!` and `#debit!` action against the ledger takes an (assumed) globally unique `transaction` id that is determined by your application.

These options combined give you reasonable guarentees that a single transaction can be retried per counter continually as long as less than X number of other transactions are applied to the same counter (where X is the `:history_length`).

The gem will automatically retry `:retry_count` number of times, and if it still fails after that you can define a secondary retry or reconciliation policy within your application to deal with the failure, although if the actions are continually failing, it is possible that something is systematically wrong with your Riak cluster.

##### Merging Siblings and Collapsing Old Transactions

Prior to every write (`#credit!` and `#debit!`), and on every read (`#find!`), two merges happen: Sibling Merges and Transaction Collapse

Sibling Merges are just combining the data from two Riak siblings into a single object, nothing extraordinary happening here.

Transaction collapse happens based on the specified or default `:history_length`. In the following example, assume `:history_length` is equal to 2:

Add 3 transactions

```
ledger = Riak::Ledger.new(client["ledgers"], "player_2", {:history_length => 2})

ledger.credit!("txn1", 10)
ledger.credit!("txn2", 10)
ledger.credit!("txn3", 10)
```

Check transaction existence

```
ledger.has_transaction? "txn1" #true
ledger.has_transaction? "txn2" #true
ledger.has_transaction? "txn3" #true
```

Based on the above, you might expect "txn1" to have been collapsed; however, merges happen only before writes, and when reads happen. This is because prior to every write, a read occurs triggering a merge. Given those facts, after a read happens, a merge should occur

```
ledger = Riak::Ledger.find!(client["ledgers"], "player_2", {:history_length => 2})

ledger.has_transaction? "txn1" #false
```

### What doesn't it do?

This gem cannot guarentee transaction idempotence over the entire lifetime of a counter for greater than `:history_length` number of transactions. If your application requires this level of idempotence on a counter, a slower reading GSet based implementation may be right for you, but keep in mind this will penalize the most active users of the counter.

#### *Notice*

##### Version 0.0.4 and Counter Drift

Scrap all that jazz - a prerequisite to using this gem is that you can guarentee that two requests for the same transaction cannot be in flight at the same time. 


In version 0.0.4 of this gem, counter drift is still a possibility. Take the following scenario into consideration:

1. Actor 1 and Actor 2 both are somehow trying to write the same transaction id, possibly because the process writing the transaction took too long, and your application erroneously had a policy of retrying the same transaction before the first actor finished.
    a. If the Actor 1 is successful in writing the transaction before Actor 2 begins, Actor 2 will see that the transaction id already exists, and will return successful before attempting to write.
    b. Similarly, if Actor 2 finishes before Actor 1 starts, Actor 1 would disregard the request and report success.
    c. If Actor 1 and Actor 2 simultaneously and successfully write the same transaction, a result of is two siblings.
2. If 1a or 1b happen, there is no problem. If 1c occurs, the second line of defense happens during a merge (merges are triggered prior to every write, and after every read).
    a. If Actor 1 merges before Actor 2, Actor 1 will remove it's own duplicate transaction in favor of leaving Actor 2's version, knowing it cannot modify any other actors' data.
    b. Similarly, if Actor 2 merges before Actor 1, it will remove it's own duplicate transaction.
    c. If Actor 1 and Actor 2 merge simultaneously and successfully, they would both remove their own duplicate (from their point of view) version of the transaction, meaning it would be lost causing negative counter drift (on increments) and positive drift (on decrements)

This is an unlikely but possible scenario. Here are some ways to reduce or elimiate the possibility of 2c from happening:

1. The precursor to the condition resulting from 2c can be avoided by serializing writes per transaction, like in the example of a game's application server knowing to only submit one unique transaction at a time. Submitting simultaneous transactions is ok, so long as the same transaction isn't active in more than one actor at the same time.
    a. This is possible using this gem, it's just a matter of implemeting some control over who can write a single unique at the same time.
2. Have a no duplicate delete policy, meaning that you could potentially have an infinitely growing list of duplicate transactions if your application causes this situation often.
    a. This is unimplemented in this gem as of now, but depending on the thoughts of others, I may add it as an optional policy.
3. Attach a microsecond epoch to each transaction so that during merges the the duplicate transaction with the highest epoch always wins.
    a. This is unimplemented in this gem, and it would only lessen the statistical likelihood of 2c happening, it would still be possible. Because it only lowers the likelihood.
4. Do a string compare on the actor ids, whichever has the highest string compare value always keeps it's version of the duplicate transaction.
    a. This is now implemented in version 0.1.0, see below.

##### Version 0.0.5 and Actor Naming [***Important***]

Solution 4 has been implemented to the potential counter drift caused by two simultaneous writes and later merges of a duplicate transaction as described in the previous section.

As a result, keep in mind that when naming actors, they will be compared for ordering purposes

Example: "ACTOR2" is greater than "ACTOR1", so ACTOR1 will always remove it's version of a duplicate transaction during a merge, and "ACTOR2" will never remove it's version. Avoid using actor ids that could potentially result in string equality.


### Further Reading

In order to attempt to best meet the requirements of *most* counters that cannot be satisfied with Riak Counters, this gem implements approach ***2b*** described in the [Problem Statement](https://github.com/drewkerrigan/riak-ruby-ledger/tree/ack-refactor#problem-statement) below as it should handle the most likely retry scenarios for most applications.

CRDT paper from Shapiro et al. at INRIA [http://hal.upmc.fr/docs/00/55/55/88/PDF/techreport.pdf](http://hal.upmc.fr/docs/00/55/55/88/PDF/techreport.pdf)

Riak Counters: [http://basho.com/counters-in-riak-1-4/](http://basho.com/counters-in-riak-1-4/)

Other Riak Data Types: [github.com/basho/riak_dt](https://github.com/basho/riak_dt)

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
require 'riak' # riak-client gem
require 'ledger' # riak-ruby-ledger gem

# Name each of your threads
Thread.current["name"] = "ACTOR1"

# Create a Riak::Client instance
client = Riak::Client.new pb_port: 8087

# Default option values
options = {
	:actor => Thread.current["name"], # Actor ID, one per thread or serialized writer
	:history_length => 10, # Number of transactions to store per actor per type (credit or debit)
	:retry_count => 10 # Number of times to retry Riak requests if they fail
}

# Create the ledger object
#                         Riak::Bucket        Key        Hash
ledger = Riak::Ledger.new(client["ledgers"], "player_1", options)
```

### Credit and debit

```
ledger.credit!("transaction1", 50)
ledger.value # 50
ledger.debit!("transaction2", 10)
ledger.value # 40

ledger.debit!("transaction2", 10)
ledger.value # 40
```

### Finding an exisitng Ledger

```
ledger = Riak::Ledger.find!(client["ledgers"], "player_1", options)
ledger.value # 40
```

### Request success

If a call to `#debit!` or `#credit!` does not return false, then the transaction can be considered saved, because it would have retried otherwise. Still, for debugging, testing, or external failure policies, `#has_transaction?` is also exposed

```
ledger.has_transaction? "transaction2" # true
ledger.has_transaction? "transaction1" # true
```

### Merging after history_length is reached

For this example, the `:history_length` is lowered to 3 so it gets reached faster.

```
options = {:history_length => 3}
ledger = Riak::Ledger.new(client["ledgers"], "player_2", options)

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

# txn3 is still in the history because the most previous write does not trigger a merge of the actor's total
# Performing a find! will trigger the merge however
ledger = Riak::Ledger.find!(client["ledgers"], "player_2", options)

ledger.has_transaction? "txn3" #false
ledger.has_transaction? "txn4" #true
ledger.has_transaction? "txn5" #true
ledger.has_transaction? "txn6" #true
```

### Deleting a ledger

```
ledger.delete()
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request