*[Aggregate]: the unit commands are addressed to; guards the rules
*[Checkpoint]: cached aggregate state, written every 100 events
*[Collaborator]: anything the domain works with but is not itself
*[Command]: a request for something to happen, which may be rejected
*[CQRS]: keeping the path that changes things separate from the reads
*[Crypto-shredding]: erasing data by deleting its encryption key
*[Driving and driven adapters]: the two sides of a hexagon
*[Event sourcing]: storing changes as events rather than as state
*[Event stream]: the ordered events belonging to one thing
*[Hexagonal architecture]: the domain at the centre, adapters around it
*[Idempotency]: doing something twice has the same effect as once
*[Mutation testing]: testing the tests by mutating the source
*[Optimistic concurrency]: refusing an append if the stream has moved on
*[Projection]: a read model built by replaying events
*[Projection system]: the machinery that keeps projections current
*[Property-based testing]: stating a property, searching for a counterexample
*[Read model]: data shaped for answering questions
*[RBI]: a file describing the types Sorbet cannot see for itself
*[Sigil]: the # typed: comment that sets Sorbet's checking level
*[Static typing]: checking data shape before the program runs
*[Upcasting]: translating an old event into the shape the code expects
