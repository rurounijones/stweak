# Glossary

## Event sourcing

State is not stored directly. Every change is recorded as
an immutable event appended to a log, and current state is derived by replaying
those events. The log is the source of truth, so nothing is overwritten or
deleted; a correction is a new event, not an edit. This gives a complete audit
trail for free, and lets new questions be asked of old data by replaying
history through a new interpretation of it.

## Event stream

The ordered sequence of events belonging to one thing, for
example a single Account. Replaying a stream from the beginning reconstructs
that thing's current state.

## Command

A request for something to happen, such as "ban this Player".
Commands are distinct from events in both tense and status: a command is an
intention that may be rejected, an event is a fact that already happened and
cannot be argued with. Handling a command means validating it against current
state and, if it holds up, appending one or more events.

## Aggregate

The unit that commands are addressed to and that guards the
rules. It is rebuilt by replaying its own event stream, decides whether a
command is allowed, and emits the resulting events. It is also the boundary of
consistency: rules can be enforced within one aggregate, but anything spanning
several of them has to be handled another way.

## Checkpoint

A cached copy of an aggregate's state at a point in its
stream. The aggregate writes one every 100 events, as its own implementation
detail, so a command handler can resume an aggregate from its latest
checkpoint plus only the events after it, rather than by replaying the whole
stream. Checkpoints are derived data: the event log remains the source of
truth, and any checkpoint can be discarded and rebuilt. They are a write-side
concern and have nothing to do with projections.

## Optimistic concurrency

Allowing concurrent work to proceed without
locking, on the assumption that conflicts are rare, and detecting them at the
moment of writing rather than preventing them in advance. Here that means an
append carries the stream position it was based on, and is refused if the
stream has moved on since.

## Upcasting

Translating an old event into the shape the code now expects,
at the point it is read. Events are immutable and the log is permanent, so when
a new field is added or a name changes, the events already written cannot be
rewritten to match. Upcasting is how the past is allowed to keep its own shape
while the present moves on.

## Read model

Any data structure shaped for answering questions rather than
for enforcing rules. Read models are built from events and are never written to
directly by users of the system.

## Projection

A read model built by replaying events into a shape convenient for querying —
in stweak, rows in the projection store's tables. Projections are materialized
in a durable projection store, yet derived and disposable: the event log
remains the source of truth, any projection can be thrown away and rebuilt
from it at any time, and several different projections can be built from the
same events. Stats in stweak are a projection.

## Projector

The code that maintains a projection: an application-layer handler that turns
the events it cares about into create/update/delete operations on the
read-model table it owns, and ignores the rest, so replaying it over the full
log always produces the same table. "Projection" is the data, "projector" the
code that produces it.

## Projection system

The machinery that builds and maintains projections: it registers on the event
subscription, feeds each projector the events it has not yet consumed, keeps
each projector's per-stream cursors durable in the projection store, and
rebuilds a projection from the beginning when its shape changes or it needs to
be replaced. It is what turns a projection from a one-off script into something
that stays current, survives a restart, and can be recreated on demand.

## Idempotency

The property that doing something twice has the same effect
as doing it once. It matters here because events may be delivered to a
projection more than once after a crash or a retry, and a projection that
counts a game twice in that situation is simply wrong.

## CQRS

Command query responsibility segregation separates the
path that changes things from the path that reads them, so each can be
designed for its own job. Writes go through commands and aggregates and
are shaped by the rules; reads come from projections and are shaped by the
questions being asked. Event sourcing does not require CQRS, but the two fit
together naturally, because an event log makes a poor thing to query directly.

## Hexagonal architecture

Also known as ports and adapters: the domain logic sits in the
middle and knows nothing about the outside world. It defines *ports*, the
interfaces describing what it needs or offers, and *adapters* implement those
ports against real technology such as a database, an HTTP framework, or a
message bus. Dependencies point inward only, so the domain can be exercised in
tests with in-memory adapters, and infrastructure choices can change without
touching business rules.

## Collaborator

Anything the domain works with but is not itself: an event
store, a clock, a source of randomness. The domain names what it needs from a
collaborator and nothing more, which is what allows the same need to be met by
several different implementations.

## Driving and driven adapters

The two sides of a hexagon. A driving adapter
calls the domain: a CLI, an HTTP API, a test harness. A driven adapter is
called by it: an event store, a queue, a clock. The distinction matters because
it is the direction of the call, not the technology, that decides which is
which.

## Mutation testing

A way of testing the tests. The tool, here mutant, makes
small changes to the source code such as flipping a condition, removing a call,
or altering a constant, then re-runs the suite. If the tests still pass, that
mutation "survived", meaning the behaviour it changed was never actually
verified. It measures whether a suite genuinely pins down behaviour, which line
coverage does not.

## Property-based testing

Describing a property that should hold for every
valid input, then letting the tool generate inputs to try to falsify it. Where
an example-based test says "3 and 4 give 7", a property says "adding two
positive numbers gives something larger than either", and the tool goes looking
for a case where that fails. When it finds one it shrinks it to the smallest
input that still breaks, which is usually the clearest description of the bug
you will get.

## Static typing

Checking claims about the shape of data before the program
runs, rather than discovering at runtime that a method received something it
could not handle. In Ruby this is a deliberate addition rather than a property
of the language.

## Sigil

The `# typed:` comment at the top of a Ruby file that tells Sorbet
how strictly to check it, from `ignore` through `false`, `true` and `strict` to
`strong`. Each level demands more of the file: at `strict`, every method must
have a signature and every constant a declared type.

## RBI

A Ruby interface file (RBI) describes the types of code
Sorbet cannot see for itself, most often a gem's public API. Generated by
tapioca and kept under `sorbet/rbi/`, they are build artefacts of a sort:
regenerated when dependencies change rather than edited by hand.

## Crypto-shredding

Deleting data that cannot be deleted, by encrypting it
and then destroying the key. The encrypted records remain in place but become
permanently unreadable, which lets an append-only event log coexist with a
legal obligation to erase personal data.
