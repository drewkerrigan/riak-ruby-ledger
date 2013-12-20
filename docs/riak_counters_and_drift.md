## Riak Counters and Drift









#### Zero Transaction History
CRDT PNCounters (two GCounters) such as Riak Counters are non-idempotent, and store nothing about a counter transaction other than the final value. As such it doesn't make sense to use them to store any counter that needs to be accurate.

#### Entire Transaction History
Another approach would be to use a CRDT GSet to store the entire set of transactions, and calculate the current value from the unique list of transaction ids. While accurate, this isn't feasible for many use cases due to the space it consumes.









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