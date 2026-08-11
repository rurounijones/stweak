# Design decisions

Choices about how the domain above is built and stored. Each is recorded with
the reasoning behind it, because the reasoning is what has to be revisited if
the decision ever stops holding.

## Domain first, adapters after

Work starts with the domain code, for the same reason the domain is described
before this section. It is the part the project is actually about, and starting
there lets the technology around it wait until the domain has enough shape to
say what it needs.

For each collaborator the domain relies on, the intention is to end up with at
least two implementations: a memory-backed or otherwise very simple one,
suitable for local work and end-to-end testing, and at least one built on a
major, well known technology, ideally two. Having more than one is the point
rather than a side effect. A collaborator with a single implementation behind
it proves nothing, because nothing has been shown to be interchangeable. One
with several, swapped freely without the domain noticing, is hexagonal
architecture doing the job it was chosen for.

The same applies to whatever calls the domain. There should be something local,
and something network callable. If the domain is genuinely independent of what
drives it, driving it two different ways should require no change to it at all.

There will also be a data generator, a caller that wraps the domain and
produces plausible events in volume. It serves as a way to stress test the
system, and as a source of realistic data to build projections against before
any real traffic exists.

## The domain's bar binds the gem, not the app area

The practices the project holds itself to — full coverage killed by mutation
testing, `typed: strict` signatures, explicit `require_relative` for every
dependency, a named type in place of a bare primitive, errors named in the
contract — are constraints on the domain gem in `lib/`. That gem is the thing
the project is a demonstration of, and it is held to them without exception.

The app area in `app/` is not that thing. Its adapters exist to prove the ports
against real technology — the [domain first, adapters
after](#domain-first-adapters-after) rule — and its drivers exist to run the
domain end to end and to generate data to build projections against. That is
integration and demonstration code. Holding it to the domain's bar would spend
effort proving nothing about the part being demonstrated, so it is exempt by
design: an adapter or driver may `require` the gem by name rather than reaching
for each class with `require_relative`, need not carry `typed: strict`, and is
not measured for mutation coverage. It still has to work — its specs run and
pass, and it is where the ports are shown to be interchangeable — but "works,
and proves the port" is a deliberately lower bar than "is the correct core".

This is why, for instance, the drivers and adapters `require 'stweak'` rather
than the domain's own `require_relative`, and why the read-only web admin is
`typed: false`: each is the app area behaving as the app area, not a lapse in
the domain's discipline. The line is the `lib/` boundary, and it is drawn on
purpose.

## CQRS

CQRS (command query responsibility segregation) keeps the path that changes
things separate from the path that reads them. This project is built around
that split rather than adopting it as an extra layer, because the design above
already points at it: an event log is a poor thing to query directly, so writes
and reads were never going to be the same shape. CQRS makes that difference
explicit and deliberate.

The write path is commands. A command is an intention, such as "create this
Account" or "ban this Player", handled against an aggregate that checks it
against current state and emits events. This path is shaped by the rules, and
is deliberately not shaped for answering questions: an aggregate is rebuilt
from its own stream so that it can enforce consistency, and reaching into one
for a read would be fighting that design.

The read path is projections. Every question the system answers, such as what
an account looks like now or how many games a player won last season, is
answered by a read model built from the event log, never by poking at aggregate
state. Read models are shaped by the questions people want to ask, which is why
they can be rebuilt and replaced as those questions change.

In practice the domain defines commands, events and aggregates and says nothing
about how any of them are delivered; the read models, and the projectors that
maintain them, are application-layer. The two sides are developed and tested
separately, and joined only by the event log between them: nothing on the read
side knows how a write happens, and nothing on the write side knows how its
events will eventually be read.

## Event versioning

Events carry a version number, and old versions are upcast on read. When an
event's shape changes, what is already in the log stays exactly as it was
written; the new version is given a new number, and reading an older one
translates it into the current shape before anything else sees it.

The alternative, rewriting history to match the code, would break the one
guarantee the log is there to provide. This way the log stays append-only and
the rest of the system only ever deals with events in their current form.

The machinery is a single seam. The domain declares how to translate an older
form: `Event.upcast(hash)` takes a serialized event and returns it in the
current shape, defaulting to identity for an event whose shape has never
changed, and overridden by an event whose schema changes to recognise an older
form by its `version` and migrate it. The read path honours that declaration —
the same "domain declares, adapter honours" boundary as encryption — applying
`upcast` before `from_h`, so `from_h` only ever sees the current shape and this
is where an event's `version` is consumed. Every store that rebuilds an event
from its stored form runs it: the durable store at its serialization boundary,
and the in-memory store, which round-trips through the serialized form on read
rather than holding live objects, so its behaviour matches the durable twin
instead of quietly skipping versioning. No real event has a second version yet,
so `upcast` is identity throughout; the seam exists so the first genuine schema
change has somewhere to live, and it is proven by a test-only event that
carries one.

## The event type name is declared, not derived

Every event declares the name it is known by in the log as an explicit constant
— `AccountCreated::TYPE` is `"AccountCreated"` — rather than deriving it from the
class. `Event#type` is abstract, the sibling of `Event#version`: each event
returns its own `TYPE` just as it returns its own `VERSION`, and the durable
registry that rebuilds an event from the wire keys on that same constant, so the
key can never drift from what the event writes.

The alternative, deriving the type from the class name, reads as less ceremony
but fails on both counts the type name has to hold to. It is a durable
identifier, so tying it to the Ruby class path means a namespace refactor
silently rewrites the stored type of every event already in the log — the one
thing an append-only log must never suffer. And it has to be unique across the
whole system, whereas a class name is only unique within its module: the domain
promises Account, Player, Season and Game each with parallel actions, so the
first two events that share a leaf name — a deleted Account and a deleted Player
— would serialize identically and collide in the registry, one silently
shadowing the other. Declaring the name is the same "declared, not discovered"
choice made for [errors](#errors-are-part-of-the-contract) and for the schema
[version](#event-versioning): the part of the serialized contract that outlives
the code is written down on purpose, not left to be an accident of where a class
currently lives.

## Concurrency

Writes use optimistic concurrency on the stream. A command is handled against
an aggregate rebuilt to a known position in its stream, and the resulting
events are only accepted if the stream is still at that position. If something
else has appended in the meantime, the write is rejected rather than applied on
top of state that has since moved.

Nothing is locked, which is the appeal: the common case, where two commands
touch different aggregates, costs nothing at all, and the rare case of genuine
contention is caught at the point it would do damage.

## Explicit requires, no autoloading

Every gem dependency is declared `require: false`, and every file requires
exactly what it uses, where it uses it. Nothing is autoloaded, and no framework
populates the namespace at boot.

This is a departure from normal Ruby and Rails convention, and it comes from
experience debugging applications rather than from theory. When loading is
implicit, "where is this class actually coming from?" is a question the source
cannot answer, and it tends to be asked at the worst possible moment. Explicit
requires make the dependency graph readable from the files themselves: what a
file needs is written at the top of it, and what the project needs is the union
of those lines rather than a convention held in someone's head.

The cost is real and worth stating. There is more ceremony, requires have to be
maintained by hand, and a missing one fails at load rather than being papered
over. That is the trade being made deliberately: a slightly noisier source in
exchange for a system whose loading can be reasoned about.

It also sits well with the rest of the design. A domain that knows nothing
about the technology around it should not be quietly handed that technology by
a framework it never asked about.

## require_relative for files we own

Files the project owns are loaded with `require_relative`; `require` is
reserved for gems and the standard library. A project file is reached by the
relative path written at the top of the file that uses it, never by a name
resolved through the load path.

The reason is that `$LOAD_PATH` is a shared, global resource. Every directory
added to it so that `require 'stweak/...'` resolves stays there for the whole
process, and the more of the project that is loadable by bare name, the closer
it comes to the implicit, unreadable loading this project already rejects.
Keeping our own files off the load path means the only way to reach one is the
explicit relative path in the file that uses it.

The cost is that moving a file to a new directory means fixing the relative
paths that point at it, a small, mechanical price for keeping the load path to
what it is actually for: the gems and the standard library.

## Static typing with Sorbet

The domain carries Sorbet signatures, checked by `srb tc` before the tests run.

A domain built from value objects, commands and events is largely a set of
claims about shape: this identifier is a UUID, this event carries exactly these
fields, this method returns a Player or raises. Those claims can be written
down and checked rather than left implicit and tested for one case at a time.
Static typing also complements mutation testing: the type checker eliminates a
whole category of mutation that would otherwise need a test to kill, leaving
the test suite to concentrate on behaviour rather than on shape.

The cost is sigils and signatures in the source, which some readers find
noisy, and gem RBIs that have to be regenerated as dependencies change. Both
seem a fair price for a project whose stated goal is being checkable.

## Types over primitives

The domain prefers a named type to a bare primitive wherever the value means
more than its class. An account id is an `AccountId`, not a `String`; a season
is a `Season`, not a number. The type system then carries meaning: a method
that accepts an `AccountId` cannot be handed a username, and a signature says
what a value is for without a reader having to guess.

This is static typing taken one step further. A signature pins down shape;
choosing the right type pins down meaning, and lets the checker catch the
confusion a bare string would hide. The cost is more types and more ceremony,
which is the same trade the project already makes for static typing, and it is
accepted for the same reason: the check happens before the code runs.

## Errors are part of the contract

An API's errors are part of its contract, named and documented like its return
values. A method that can fail says what it raises, and a caller can depend on
that list rather than discovering failures by reading the body. Errors are
reserved for situations that are genuinely errors — something that should not
have happened, given the rules — not for steering control flow.

This is the sibling of static typing. A signature describes what a method takes
and returns, but a contract is incomplete without what can go wrong. Naming an
error for what it means, an account that already exists or a key that is not
there, is the same explicitness the project applies everywhere else: the
behaviour of a method is declared, not discovered.

## Objects validate themselves at construction

The domain's value objects, commands and events validate themselves when they
are built. An object that cannot be made valid does not come into existence:
its constructor raises rather than returning a potentially invalid instance
that might later be handed to a service.

The reason is blunt. If a command can be constructed in a state its handler
then has to check for, that invalid state will eventually be constructed and
passed around, and the failure will surface far from where the mistake was
made. Making construction the only way to create an object, and refusing
invalid input at that point, means an invalid object is not merely unlikely.
It is unrepresentable.

This is the same kind of claim the project makes elsewhere, moved earlier in
time. Sorbet signatures pin down the shape of an object before the program
runs, and constructor validation pins down whether that shape is a legal one at
the moment it is filled in. Between the two, by the time a handler receives a
command, both its type and the validity of its contents are already settled.

None of this replaces the checks that decide whether a command is allowed.
Whether a command is well-formed is one question, and whether it is allowed is
another, and how the second is answered depends on the rule. One that lives
within a single aggregate — such as an account having already been created —
is checked by the aggregate itself. One that spans aggregates, such as a
username being unique across all accounts, cannot be: no single aggregate can
see the others, so it is checked at handling time against the read model of
usernames. This decision guarantees that the first question never goes
unanswered, because a broken object cannot be built.

## Encryption at the event-store boundary

The event class declares which fields are personal data — for example,
`AccountCreated.pii_fields` returns `[:name]`. That declaration is a business
rule, a statement of what the law requires to be erasable, so it lives in the
domain. The cryptography that honours it lives in an adapter: an
`EncryptingEventStore` decorates a raw event store, encrypting every PII field
on append and decrypting it back on read. The domain emits and receives the
plaintext name and never knows what AES-256-GCM is.

The cipher is AES-256-GCM with a random 256-bit key and a fresh nonce per
encryption; the nonce and authentication tag are stored alongside the
ciphertext, so each encrypted value is self-contained. Keys are created
implicitly on first use, held per entity that owns personal data, and stored in
a key store outside the event log — the crypto-shredding design from the
[GDPR][gdpr] section. An entity is an aggregate class and an id: keys are
qualified with the owner's class, so an Account and a Player that happen to
share an id never share a key.

## Password hashing happens in the domain, through a port

`CreateAccount` carries the raw password, and the handler hashes it through a
`PasswordHasher` port before the aggregate ever sees it. The raw password never
reaches the event log, and a caller — a future CLI or HTTP adapter — never
touches hashing at all.

The implementation is PBKDF2-HMAC-SHA256 with a per-password random salt, using
only the stdlib. The stored value is self-describing
(`pbkdf2-sha256$<iterations>$<salt>$<hash>`), so verification can be added
later without changing what is stored. The method is named `digest` rather than
`hash` because `hash` collides with `Kernel#hash`, which would make an
implementor unusable as a hash key.

## The handler is an application service

`CreateAccountHandler` lives in the domain layer, not in a driving adapter. It
hashes the command's password, drives the aggregate, and appends to the event
store; the command validated itself when it was built. It is deliberately
built to be driven two different ways — something local, something network
callable — without any change to the domain, per the [domain first, adapters
after](#domain-first-adapters-after) decision.

## Command idempotency is derived, not caller-supplied

A retried command should produce its original result, not a fresh error: if a
client's request times out and is sent again, the second create of the same
account should return the account, not raise. There is no caller-supplied
idempotency key — the callers of this domain are not trusted to manage one —
so the key is derived from the command itself. For `CreateAccount` it is the
username: the account id names the aggregate, and the username is what a retry
carries unchanged. The account stores the username of the command that created
it, so a retry is recognized by replaying the account and comparing usernames:
a match returns the account, and a mismatch is a genuine second create and
raises.

The limitation is the deliberate price of deriving the key from parameters: a
retry is recognized by the username alone, so one that changed its password or
display name is still treated as the same command. Hashing makes a password
incomparable, and the username is the part of the command that names the thing
being created; this is an idempotency key, not a guarantee of command equality.

## The read side is fed by a transport, not the event store

The event store emits appended events to a *subscription* — a port that
delivers them to whoever has registered as a listener. The store's append
publishes and knows nothing about the listeners; a listener registers and
knows nothing about the emitter; the two meet only at the port. In memory the
delivery is a synchronous callback in the publishing process, so a listener
hears every append as it happens. In production the same port would be
implemented over a queue such as SQS: the publish side sends the events to the
queue, a consumer reads from it, and delivery is out of process. The domain
depends on the port and nothing else, so the in-memory and queue
implementations are interchangeable without touching it. Delivery is
at-least-once — a listener may receive a batch more than once — and tolerating
that is the listener's job. The projection system is the natural listener.

## Projections are materialized and durable

The read models are projections: derived data materialized in the projection
store — a relational database, SQLite in the app area with an in-memory twin
in the domain gem — so they can be queried and so they survive a restart. A
projection is a *projector*: an application-layer handler that turns the events
it cares about into create/update/delete operations on the read-model table it
maintains, and ignores the rest, so replaying it over the full log always
produces the same table. The database therefore looks like a normal application
database — an accounts table, keyed by account — with one extra table of
machinery: `projection_cursors` holds one indexed row per (projection, stream)
recording the highest sequence consumed, so a restarted projector resumes from
each stream's cursor instead of replaying every stream. The event log remains
the source of truth — a projection is derived and disposable in the sense that
it can be discarded and rebuilt from the streams at any time, not in the sense
that it is transient. The projection system keeps each projector current: it
registers on the subscription, feeds it the events it has not yet consumed, and
persists its cursors after every batch. Re-delivered events are skipped by the
per-stream cursor, so the system is safe under the subscription's at-least-once
delivery.

Personal data in a read model is encrypted at the store boundary, the same
crypto-shredding boundary as the event store: the accounts table stores the
account's display name and email encrypted under a per-account key, and
deleting the key renders them unreadable. Usernames and password hashes are
deliberately not encrypted — the username must survive shredding so the
uniqueness check keeps working, and a password hash is already unreadable.

## Checkpoints are the aggregate's implementation detail

Every 100 events on an aggregate's stream, the aggregate's state is saved to
the checkpoint store as a checkpoint, so a command handler can resume an
aggregate from its latest checkpoint plus only the events after it, instead of
replaying the whole stream. The checkpointing logic is the aggregate's: replay
restores from a checkpoint and applies only the tail, the aggregate decides
when one is due, and it serializes its own state. The handler's part is
mechanical — it passes a stored checkpoint into replay and persists whatever
checkpoint the aggregate reports after a successful append — so nothing
outside the aggregate can tell whether a replay used a checkpoint or not. A
checkpoint is derived data: the event log remains the source of truth, and any
checkpoint can be discarded and rebuilt.

Two things follow from this. A checkpoint carries the aggregate's serialized
state, including personal data such as an account's display name and email, so
a durable checkpoint store encrypts it — the same crypto-shredding boundary as
the event store. An `EncryptingCheckpointStore` decorates the durable store,
encrypting each state key the aggregate declares as personal data before the
checkpoint is persisted and decrypting it back on read; which keys those are is
the aggregate's own declaration (`checkpoint_pii_fields`), because the state is
the aggregate's serialization of itself and naming its personal data is a
domain business rule, the same as `Event.pii_fields`. The in-memory checkpoint
store holds plaintext, accepted while everything is in memory. And the handler
reads only the tail: when a checkpoint is present it reads the events after the
checkpoint's version through the event store's range read (`read_stream`'s
`after:` bound) rather than reading the whole stream and letting replay skip
the prefix, so a checkpoint saves the read as well as the replay. The whole
stream is just the `after: 0` case of the same read, so nothing outside the
handler has to know which path was taken.

## Observability stays out of the domain

The domain does not log, and it does not emit metrics. Observability is a
concern of the technology around the domain, not of the rules themselves, and
putting it in the domain would leak an infrastructure concern into the very
part of the system that is meant to stay pure. When telemetry is genuinely
needed, it is added from outside: a module prepended onto the domain class, or
a wrapper around it, that logs and times and counts while the wrapped class
stays exactly as it was.

This is the same boundary as encryption. There, the domain declares which
fields are personal data and an adapter honours it; here, the domain does its
work and a decorator records it. The domain is left plain, and the
instrumentation can be swapped in and out without the domain knowing.

## All datastores are in-memory for now

In the domain gem, the event store, the key store behind it, the checkpoint
store, and the projection store each have an in-memory adapter, so nothing
survives a restart by default. The app area holds the durable twins — the
DynamoDB event store, the Redis key and checkpoint stores, and the SQLite
projection store — so each collaborator meets the two-implementations rule
above. The SQLite projection store is a fully relational read-model database
rather than a keyed blob: read models are rows in their own tables, with
per-stream cursors in a shared `projection_cursors` table.

## Property-based testing, as research

Property-based testing states what should be true of all inputs and lets the
tooling search for a counterexample, rather than asserting one example at a
time. In principle it pairs well with what is already here: mutation testing
asks whether the tests pin behaviour down, and property tests generate the
cases nobody thought to write.

In practice the author has no experience with it at all. It is being tried
because it looks like a good fit, not because it is known to be one, and it may
turn out to be a poor match for this domain or simply more trouble than it is
worth.

[gdpr]: index.md#gdpr
