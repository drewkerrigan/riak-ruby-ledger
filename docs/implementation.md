## Implementation

### Summary

The data type implemented is a PNCounter CRDT with an ordered array of transactions for each GCounter actor. Transaction ids are stored with the GCounter, so operations against this counter are idempotent while the transaction remains in any actor's array.

**High Level API**

Function | Description
--- | ---
`Riak::Ledger.new` | Creates a new Ledger instance
`Riak::Ledger.find!` | Finds an existing Ledger in Riak, merges it locally, and then writes the merged value back to Riak
`#credit!`, `#debit!`, `#update!` | Reads the existing state of the ledger from Riak, merges it locally, and adds a new `transaction` and positive or negative `value`

**Ledger Options**

Name | Description
--- | ---
`:retry_count`[Integer] | When a write to Riak is a "maybe" (500, timeout, or any other error condition), resubmit the request `:retry_count` number of times, and return false if it is still unsuccessful
`:history_length`[Integer] | Keep up to `:history_length` number of transactions in each actor's section of the underlying GCounter. When the (`:history_length` + 1)th transaction is written, add the oldest transaction's value to the actor's total

### GCounters

A typical GCounter data structure looks something like this:

```
{
    "actor1": 10,
    "actor2": 20,
    "actor3": 5
}
```

Since no actor can affect any other actor's total, this is a safe way to increment a single number in a concurrent way. The total value of this counter is defined by the totals of all actors summed

### PNCounters

Because GCounters only allow for a counter to increment, a simple way to allow for decrements is to use two GCounters. A PNCounter is defined by two GCounters, one for increments, and one for decrements.

```
{
    "p": <GCounter>,
    "n": <GCounter>,
}
```

"p" is for positive, and "n" is for negative, so the current value of a PNCounter is defined by P minus N.

### TPNCounter and TGCounter (unique to this gem and it's functionality)

For idempotent operations over a limited window of transactions, an array of transactions can be stored with each actor's counter value. The mechanics of the GCounter are unchanged, but the method with which the single total value for an actor gets incremented is dependent upon the current size of the transaction list.

The new data structure for the GCounter portion of this gem's PNCounter looks like this:

```
{
    "actor1": {"total": 10, "txns": [["txn1": 5],["txn2": 1],["txn3":10]]},
    "actor2": {"total": 20, "txns": [["txn4": 5],["txn5": 1],["txn6":10]]},
    "actor3": {"total": 5, "txns": [["txn7": 5],["txn8": 1],["txn9":10]]}
}
```

Since these are not true PN or G counters, in the code they are named `Riak::CRDT::TPNCoutner` and `Riak::CRDT::TGCounter` (T for transaction)

#### History Length

The history length option determines the maximum length of the transaction array per actor before that actor will start removing (oldest first) transactions from its list. Take the following code example into consideration:

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

#### Edge Case: Duplicates

**First line of defense**

Before every write, the Ledger class will read the current value of the counter from Riak, if it already exists, the operation will not continue because the transaction has already been placed.

It is possible to have duplicate transactions in across multiple actors however if the following happens:

1) Actor 1 attempts to write transaction1, but is taking a long time to do so for some reason
2) Your application decides that Actor 1 has taken too long, and issues the same transaction to Actor 2 for writing
3) Since Actor 1's version of the transaction is still in flight, it could finish successfully while Actor 2's write of transaction1 was also successful

This situation would result in siblings getting created where the merged result ends up being 2 actors with the same transaction1

**Second line of defense**

Upon Actor 2's or Actor 1's next merge, they will find that there is indeed a duplicate, and the following logic happens in order to deal with the duplicate:

1) A merge occurs, and a string comparison on the actors' ids takes place to see who should own the transaction
    a) If Actor 1 is merging, "ACTOR1" is less than "ACTOR2", so Actor 1 gets rid of the transaction without counting it
    b) If Actor 2 is merging, "ACTOR2" is greater than "ACTOR1", so Actor 2 keeps the transaction, knowing that Actor 1 should delete it

This approach allows for the case in which Actor1 and Actor2 are simultaneously merging, similarly to when they simultaneously added the transaction

It is quite possible however for Actor 1 to become stale, and never get rid of the transaction as they should have...

**Third and final line of defense**

The following workflow should be read in the voice of Actor 2:

If we have held onto a duplicate this long, we meet the following criteria:
1) We are the actor who is supposed to keep this duplicate while the other removes it
2) We have had enough time to do :history_length number of transactions since the other actor
    has performed a merge
3) If they stay dormant and the txn remains untouched there, I shouldn't count it
4) If they are currently merging and about to count it, I also shouldn't count it for fear of counting it twice,
5) The third possibility is the following:
    Actor 1 attempts to write transaction 1, it takes a long time, application decides to retry after timeout
    Actor 2 manages to successfully write transaction 1, and then :history_length - 1 more writes and
      is currently deciding what to do with that transaction ("hmmm, should I count it?")
    While that merge is happening, Actor 1 finally finishes writing transaction 1 and now Actor 2's
      request is taking a long time for some reason
    While still waiting on Actor 2, Actor 1 performs another merge and sees that Actor 2 has transaction 1
      knowing it is the inferior actor, Actor 1 removes without counting. But at this stage, Actor 2 wouldn't have known that Actor 1 ever even had transaction 1, and would have correctly counted the value

Given that 5) would actually be handled by the second line of defense, this leaves us with 3) and 4). Since both of those situations result in Actor 1 counting the value, during the compression phases of Actor 2's merge, if the duplicate transaction is about to be deleted, Actor 2 would remove the transaction without counting it towards it's own total.









 ## Other Possible Approaches to the Idempotent Counter Problem

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
