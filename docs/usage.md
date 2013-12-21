## Suggested Usage and Configuration

### Summary

Depending on your use case, you may want to tweak the configuration options `:history_length` and `:retry_count`.

The default `:history_length` is 10. This means that if a transaction fails, but your application is unable to determine whether or not the counter was actually incremented, you have a buffer space or window of 9 additional transactions on that counter before you can no longer retry the original failed transaction without assuming counter drift is happening.

The default `:retry_count` is also 10. This means that if a transaction fails, the actor that attempted the transaction will continue trying 9 more times. If the request to change the counter still fails after the 10th try, the operation will return `false` for failure. At this point your application can attempt to try the transaction again, or return a failure to the user with a note that the transaction will be retried in the future.

An example of a failure might look like the following:

1. transaction1 fails with actor1, and because of the nature of the failure, your application is unsure whether or not the counter was actually incremented.

	1. If your `:retry_count` is low, you can quickly determine in your application that something went wrong, and inform the user that the transaction was unsuccessful for now, but will be attempted later
	2. If your `:retry_count` is high, the user will be kept waiting longer, but the odds of the transaction eventually working are higher
2. If after the initial retries, the transaction was still a failure, your application must decide what to do next

	1. If your `:history_length` is low, your options are limited. You must continue to retry that same failed transaction for that user (using any available actor) until it is successful. If you allow additional transactions to take place on the same counter before retrying, you run a high risk of counter drift.
	2. If your `:history_length` is medium-high, then you have an allowance of (`:history_length` - 1) additional transactions for that counter before you run the risk of counter drift.

**Note**

This gem cannot guarentee transaction idempotence of a counter for greater than `:history_length` number of transactions.

### Tunable Transaction History
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

### :retry_count values

A low `:retry_count` (1-9) might be appropriate for applications that would rather give immediate failed request feedback to their users so that they can continue performing other actions. This should be coupled with a higher `:history_length` if you intend to allow your user to initiate other transactions while waiting to retry the first one.

A medium `:retry_count` (10-50) might be appropriate for applications that require a higher level of certainty about a specific transaction's success at all times. Allowing a single actor to attempt retries for as long as necessary also greatly reduces the chance that duplicate transactions will ever be created, but requests will take longer in that case. Even if duplicate transactions are created, they should be merged at a later time, but it is safer to have a 1 actor per transaction at a time policy.

### :history_length values

A low `:history_length` (1-9) is never really suggested, as it lowers the time window for idempotent operations to occur. The only time a low `:history_length` might be necessary is if your cluster is not big enough to handle the space consumed by the transaction list. Here is an example calculation to show how much space various transaction histories might consume.

```
# Riak's replication value
n = 3
actor_count = 5
# a single transaction within counter json might
# look like this: ["550e8400-e29b-41d4-a716-446655440000": 10],
bytes_per_txn = 45
# if you have 1 million users, and 1 ledger per user
number_of_counters = 1,000,000
```

For a `:history_length` of 10:

```
(actor_count * number_of_counters * bytes_per_txn * history_length) * n = 6750000000 bytes or 6.28643 GB total raw disk storage
```

For a `:history_length` of 50:

```
(actor_count * number_of_counters * bytes_per_txn * history_length) * n = 33750000000 bytes or 31.4321 GB total raw disk storage
```

A medium `:history_length` (10-50) is a safe balance for most applications. Applications suited for this range of values are ones that do not have very high concurrent access requirements on a per counter basis. For example an application that only allows a user to have one transaction in flight at a time, but wants the option to let the user continue doing a few more transactions before the state of the failed transaction is known.

A high `:history_length` (50+) might be suitable for applications whose primary function is to provide highly concurrent and frequent access to a limited number of counters. An example might be a service that needs to keep accurate track of a limited number of statistics like how much bandwidth is consumed for a series of endpoints for the purposes of billing a customer.