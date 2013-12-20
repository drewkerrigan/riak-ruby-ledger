## Implementation

The data type implemented is a PNCounter CRDT with a fixed length GSet for each GCounter actor. Transaction ids are stored in the GSet, so operations against this counter are idempotent while the transaction remains in the set.

PN Counters

G Counters

G Sets

Fixed length gset

data structure

duplicates

If we have held onto a duplicate this long, we meet the following criteria:
1) We are the actor who is supposed to keep this duplicate while the other removes it
2) We have had enough time to do :history_length number of transactions since the other actor
    has performed a merge
3) If they stay dormant and the txn remains untouched there, I shouldn't count it
4) If they are currently merging and about to count it, I also shouldn't count it,
5) If they are currently merging, but not about to count it, they could remove it if:
    Actor 1 attempts to write transaction 1, it takes a long time, application decides to retry after timeout
    Actor 2 manages to successfully write transaction 1, and then :history_length - 1 more writes and
      is currently deciding what to do with that transaction ("hmmm, should I count it?")
    While that merge is happening, Actor 1 finally finishes writing transaction 1 and now Actor 2's
      request is taking a long time for some reason
    While still waiting on Actor 2, Actor 1 performs another merge and sees that Actor 2 has transaction 1
      knowing it is the inferior actor, Actor 1 removes without counting. But at this stage, Actor 2 wouldn't have known that Actor 1 ever even had transaction 1, and would have correctly counted the value


 how they are created

 how they are dealt with