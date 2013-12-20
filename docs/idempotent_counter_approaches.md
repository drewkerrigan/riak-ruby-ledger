## Idempotent Counters

There are several approaches to making counters varying degrees of idempotent, the ones relative to the goals of this gem described here.

### Definitions

* ***Transaction id***: Globally unique externally generated transaction id that is available per counter action (increment or decrement)
* ***Actor***: A thread, process, or server that is able to serially perform actions (a single actor can never perform actions in parallel with itself)
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

Actor 1 writes txn1: 50, txn2: 10, txn3: 100 (order is preserved using an array instead of a hash for transactions)

```
Actor1: {"total": 0} [["txn1", 50], ["txn2", 10], ["txn3", 100]]}
```

Actor 2 attempts to write txn1: 50

Actor 2 reads current value and sees that txn1 has already been written, ignores it's own txn1

Actor 2 writes merged value

```
Actor1: {"total": 0} [["txn1", 50], ["txn2", 10], ["txn3", 100]]
```

Actor 2 Writes txn4: 100

```
Actor1: {"total": 0} [["txn1", 50], ["txn2", 10], ["txn3", 100]]
Actor2: {"total": 0} [["txn4", 100]]
```

Actor 1 Writes txn5: 20, txn6: 20

```
Actor1: {"total": 0} [["txn1", 50], ["txn2", 10], ["txn3", 100], ["txn5", 20], ["txn6", 20]]
Actor2: {"total": 0} [["txn4", 100]]
```

Actor 1 Writes txn7: 30, and writes it's own merged data

```
Actor1: {"total": 50} [["txn2", 10], ["txn3", 100], ["txn5", 20], ["txn6", 20], ["txn7", 30]]
Actor2: {"total": 0} [["txn4", 100]]
```

Actor 1 reads and merges value

```
Actor1: {"total": 50} [["txn2", 10], ["txn3", 100], ["txn5", 20], ["txn6", 20], ["txn7", 30]]
Actor2: {"total": 0} [["txn4", 100]]
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
