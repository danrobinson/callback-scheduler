# Callback Scheduler [WIP]

A Solidity contract that enables scheduling callbacks, which can be executed in a specified future transaction at a specified block number and priority. The gas for the callback is paid upfront by the user through a deposit.

This contract could be used on any EVM chain, but it would be most useful if given special support by builders on a priority-ordered L2. Block builders could provide an out-of-protocol guarantee that every callback will be called (unless the block is full), by monitoring for CallbackScheduled events and creating a transaction that executes the callback at the specified position. This could even allow for a transaction to schedule a callback to be executed later in the same block.

The ability to dynamically schedule transactions for later in the same block allows a wider range of auctions to be implemented within the priority-ordering paradigm. For example, batch auctions could be implemented by having the first transaction that submits an order into the batch schedule a callback to settle the entire batch at the end of the block. It also allows for more sophisticated bidding strategies in multi-round priority auctions, since bidders could submit a transaction that dynamically computes their bid in a later round based on information revealed in previous rounds.

This contract is a work in progress and not ready for production use.