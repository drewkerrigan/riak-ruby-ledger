## Implementation

### Summary

The data type implemented is a PNCounter CRDT with an ordered array of request_ids for each GCounter actor. Request ids are stored with the GCounter, so operations against this counter are idempotent while the request_id remains in any actor's array.

**High Level API**

Function | Description
--- | ---
`Riak::Ledger.new` | Creates a new Ledger instance
`Riak::Ledger.find!` | Finds an existing Ledger in Riak, merges it locally, and then writes the merged value back to Riak
`#credit!`, `#debit!`, `#update!` | Reads the existing state of the ledger from Riak, merges it locally, and adds a new `request_id` and positive or negative `value`

**Ledger Options**

Name | Description
--- | ---
`:retry_count`[Integer] | When a write to Riak is a "maybe" (500, timeout, or any other error condition), resubmit the request `:retry_count` number of times, and return false if it is still unsuccessful
`:history_length`[Integer] | Keep up to `:history_length` number of request_ids in each actor's section of the underlying GCounter. When the (`:history_length` + 1)th request_id is written then merged, add the oldest request_id's value to the actor's total

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

### TPNCounter and TGCounter (unique to this gem and its functionality)

For idempotent operations over a limited window of request_ids, an array of request_ids can be stored with each actor's counter value. The mechanics of the GCounter are unchanged, but the method with which the single total value for an actor gets incremented is dependent upon the current size of the request_id list.

The new data structure for the GCounter portion of this gem's PNCounter looks like this:

```
{
    "actor1": {"total": 10, "requests": ["req1","req2","req3"]},
    "actor2": {"total": 30, "requests": ["req4","req5","req6"]},
    "actor3": {"total": 5, "requests": ["req7","req8","req9"]},
}
```

Since these are not true PN or G counters, in the code they are named `Riak::CRDT::TPNCoutner` and `Riak::CRDT::TGCounter` (T for request_id)

#### History Length

The history length option determines the maximum length of the request_id array per actor before that actor will start removing (oldest first) request_ids from its list. Take the following code example into consideration:

For this example, the `:history_length` is lowered to 3 so it gets reached faster.

```
options = {:history_length => 3}
ledger = Riak::Ledger.new(client["ledgers"], "player_2", options)

ledger.credit!(10, "req1")
ledger.credit!(10, "req2")
ledger.credit!(10, "req3")
ledger.credit!(10, "req4")
ledger.credit!(10, "req5")
ledger.credit!(10, "req6")

ledger.value #60

ledger.has_request_id? "req1" #false
ledger.has_request_id? "req2" #false
ledger.has_request_id? "req3" #true

# req3 is still in the history because the most previous write does not trigger a merge of the actor's total
# Performing a find! will trigger the merge however
ledger = Riak::Ledger.find!(client["ledgers"], "player_2", options)

ledger.has_request_id? "req3" #false
ledger.has_request_id? "req4" #true
ledger.has_request_id? "req5" #true
ledger.has_request_id? "req6" #true
```

### Definitions

 * ***Request id***: Globally unique id that is available per counter action (increment or decrement), uuid is generated if none is given
 * ***Actor***: A thread, process, or server that is able to serially perform actions (a single actor can never perform actions in parallel with itself)
 * ***Sibling***: In Riak, when you write to the same key without specifying a vector clock, a sibling is created. This is denoted below as `[...sibling1..., ...sibling2...]`.

### Approach 1: Ensure idempotent counter actions at any time, by any actor

 This is possible if the entire request_id history is stored inside of the counter object:

 Actor 1 writes req1: 50

 ```
 {"req1": 50}
 ```

 Actor 2 writes req1: 50, req2: 100

 ```
 [
 	#sibling 1
 	{"req1": 50},
 	#sibling 2
 	{"req1": 50, "req2": 100}
 ]
 ```

 Actor 1 reads and merges value

 ```
 {"req1": 50, "req2": 100}
 ```

 Total: 150

 This is not a counter, but a ***GSet***, because the entire set of request_ids needs to be stored with the object. The total for a counter is defined by the sum of the entire set of values

 ***Pros***:

 * Retry any action at any time by any actor in the system.
 * Optimize for writes: No need to read the value prior to writing a new request_id.

 ***Cons***:

 * GSet sizes can become too large for ruby to handle. If more than ~1000 request_ids are expected for a single counter, this approach should not be used


### Approach 2a: Ensure idempotent counter actions by any actor, for the current request_id

 In this approach, the request_id id is stored per actor for the most recently written request_id

 Actor 1 writes req1: 50

 ```
 Actor1: {"total": 0} {"req1": 50}
 ```

 Actor 2 attempts to write req1: 50

 Actor 2 reads current value and sees that req1 has already been written, ignores it's own req1

 Actor 2 writes merged value

 ```
 Actor1: {"total": 0} {"req1": 50}
 ```

 Actor 2 Writes req2: 100

 ```
 Actor1: {"total": 0} {"req1": 50}
 Actor2: {"total": 0} {"req2": 100}
 ```

 Actor 2 Reads current value, and writes req3: 10 along with it's own merged data

 ```
 Actor1: {"total": 0} {"req1": 50}
 Actor2: {"total": 100} {"req3": 10}
 ```

 Actor 1 reads and merges value

 ```
 Actor1: {"total": 0} {"req1": 50}
 Actor2: {"total": 100} {"req3": 10}
 ```

 Total: 160

 ***Pros***:

 * Retry an action with any actor in the system, assuming the actions are serialized per counter
 * Optimize for reads: Since a very small amount of data is stored in the counter, reads should be very fast

 ***Cons***:

 * Counter drift is a possibility in the case where request_id 1 fails, several other request_ids succeed without retrying request_id 1, and then request_id 1 is tried again

### Approach 2b: Ensure idempotent counter actions by any actor, for the previous `X` request_ids

 This approach is the same as 2a, but instead of only storing the most previous request_id, we store the most previous `X` request_ids. In this example we'll use X=5

 Actor 1 writes req1: 50, req2: 10, req3: 100 (order is preserved using an array instead of a hash for request_ids)

 ```
 Actor1: {"total": 0} [["req1", 50], ["req2", 10], ["req3", 100]]}
 ```

 Actor 2 attempts to write req1: 50

 Actor 2 reads current value and sees that req1 has already been written, ignores it's own req1

 Actor 2 writes merged value

 ```
 Actor1: {"total": 0} [["req1", 50], ["req2", 10], ["req3", 100]]
 ```

 Actor 2 Writes req4: 100

 ```
 Actor1: {"total": 0} [["req1", 50], ["req2", 10], ["req3", 100]]
 Actor2: {"total": 0} [["req4", 100]]
 ```

 Actor 1 Writes req5: 20, req6: 20

 ```
 Actor1: {"total": 0} [["req1", 50], ["req2", 10], ["req3", 100], ["req5", 20], ["req6", 20]]
 Actor2: {"total": 0} [["req4", 100]]
 ```

 Actor 1 Writes req7: 30, and writes it's own merged data

 ```
 Actor1: {"total": 50} [["req2", 10], ["req3", 100], ["req5", 20], ["req6", 20], ["req7", 30]]
 Actor2: {"total": 0} [["req4", 100]]
 ```

 Actor 1 reads and merges value

 ```
 Actor1: {"total": 50} [["req2", 10], ["req3", 100], ["req5", 20], ["req6", 20], ["req7", 30]]
 Actor2: {"total": 0} [["req4", 100]]
 ```

 Total: 330

 ***Pros***:

 * Retry an action with any actor in the system, for the last X actions
 * Optimize for reads: Since a very small amount of data is stored in the counter, reads should be very fast

 ***Cons***:

 * Counter drift is a possibility in the case where request_id 1 fails, X + 1 actions occur, and request_id 1 is retried

### Approach 3: Ensure idempotent counter actions by a single actor, for the current request_id

 In this approach, a globally unique request_id id is no longer required, because we are assuming that only a single actor can ever be responsible for a single request_id

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

 * No reliance on an external globally unique request_id id
 * Optimize for reads: Since a very small amount of data is stored in the counter, reads should be very fast

 ***Cons***:

 * Counter drift is a possibility if any action is retried by someone other than the current actor during it's current request_id

## Conclusion

 In order to attempt to best meet the requirements of *most* counters that cannot be satisfied with Riak Counters, this gem implements approach ***2b*** as it should handle the most likely retry scenarios for most applications.
