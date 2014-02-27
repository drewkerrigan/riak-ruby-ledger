## Release notes

##### Version 0.0.4 and Counter Drift

In version 0.0.4 of this gem, counter drift is still a possibility. Take the following scenario into consideration:

1. Actor 1 and Actor 2 both are somehow trying to write the same request_id id, possibly because the process writing the request_id took too long, and your application erroneously had a policy of retrying the same request_id before the first actor finished.
    1. If the Actor 1 is successful in writing the request_id before Actor 2 begins, Actor 2 will see that the request_id id already exists, and will return successful before attempting to write.
    2. Similarly, if Actor 2 finishes before Actor 1 starts, Actor 1 would disregard the request and report success.
    3. If Actor 1 and Actor 2 simultaneously and successfully write the same request_id, a result of is two siblings.
2. If 1a or 1b happen, there is no problem. If 1c occurs, the second line of defense happens during a merge (merges are triggered prior to every write, and after every read).
    1. If Actor 1 merges before Actor 2, Actor 1 will remove it's own duplicate request_id in favor of leaving Actor 2's version, knowing it cannot modify any other actors' data.
    2. Similarly, if Actor 2 merges before Actor 1, it will remove it's own duplicate request_id.
    3. If Actor 1 and Actor 2 merge simultaneously and successfully, they would both remove their own duplicate (from their point of view) version of the request_id, meaning it would be lost causing negative counter drift (on increments) and positive drift (on decrements)

This is an unlikely but possible scenario. Here are some ways to reduce or elimiate the possibility of 2c from happening:

1. The precursor to the condition resulting from 2c can be avoided by serializing writes per request_id, like in the example of a game's application server knowing to only submit one unique request_id at a time. Submitting simultaneous request_ids is ok, so long as the same request_id isn't active in more than one actor at the same time.
    1. This is possible using this gem, it's just a matter of implemeting some control over who can write a single unique at the same time.
2. Have a no duplicate delete policy, meaning that you could potentially have an infinitely growing list of duplicate request_ids if your application causes this situation often.
    1. This is unimplemented in this gem as of now, but depending on the thoughts of others, I may add it as an optional policy.
3. Attach a microsecond epoch to each request_id so that during merges the the duplicate request_id with the highest epoch always wins.
    1. This is unimplemented in this gem, and it would only lessen the statistical likelihood of 2c happening, it would still be possible. Because it only lowers the likelihood.
4. Do a string compare on the actor ids, whichever has the highest string compare value always keeps it's version of the duplicate request_id. If one the lesser actor is stale and never merges, the actor that should keep the request_id will throw it away knowing that the stale actor will keep it.
    1. This is now implemented in version 0.0.5, see below.

##### Version 0.0.5 and Actor Naming [***Important***]

Solution 4 has been implemented to the potential counter drift caused by two simultaneous writes and later merges of a duplicate request_id as described in the previous section.

As a result, keep in mind that when naming actors, they will be compared for ordering purposes

Example: "ACTOR2" is greater than "ACTOR1", so ACTOR1 will always remove it's version of a duplicate request_id during a merge, and "ACTOR2" will never remove it's version unless it thinks actor 1 is stale. Avoid using actor ids that could potentially result in string equality.

##### Version 0.0.5

Removed the automatic setting of allow_mult on the bucket in Riak::Ledger. Please remember to set allow_mult to true on your ledger bucket, notes in README.md