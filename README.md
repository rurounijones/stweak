# stweak

Player account management for a theoretical online team PvP game.

stweak is the system of record for who a player is and what happened to them.
It owns accounts, the players attached to those accounts, the seasons the game
is divided into, and the games played within a season. It does not run matches
and it is not the game server; it is the book of record that sits behind one.

The project makes use of various design and architecture approaches such as
event-sourcing and hexagonal architecture. It is a research project for the
author as much as a potential example for others, and is being developed with
the help of AI as a way to speed up development.

The strict practices the project holds itself to — full mutation-tested
coverage, static typing, explicit requires, a type over a bare primitive — apply
to the domain gem in `lib/`, which is the artifact. The `app/` area is
integration and demonstration code: it proves the ports against real technology
and drives the domain end to end, and is deliberately not held to the same bar.

## Documentation

The full documentation — the domain model, the architecture and design
decisions, the glossary, and the developer guide — lives at
<https://rurounijones.github.io/stweak/>.

## License

Copyright (C) 2026 Jeffrey Jones.

Released under the GNU Affero General Public License, version 3 or later. See
[LICENSE](LICENSE) for the full text.
