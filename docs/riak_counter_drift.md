## Riak Counters and Drift

### Summary

**Why shouldn't I use Riak Counters?**

CRDT PNCounters (two plain GCounters) such as Riak Counters are non-idempotent and store nothing about a counter request_id other than the final value. This means that if an increment operation fails in any number of ways (500 response from server, process that made the call dies, network connection is interrupted, operation times out, etc), your application now has no idea whether or not the increment actually happened.

**What is Counter Drift?**

In the above situation of a failed increment operation, your application has two choices:

1. Retry the operation: This could result in the operation occuring twice causing what is called **positive counter drift**
2. Don't retry the operation: This could result in the operation never occuring at all causing **negative counter drift**

As such it doesn't make sense to use plain GCounters or PNCounters to store any counter that needs to be accurate.

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

Riak Counters (and GSets in general) as currently implemented are not ***idempotent***. This simply means that you cannot retry the same increment or decrement operation more than once.

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