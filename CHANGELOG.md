# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog][keepachangelog], and this project
adheres to [Semantic Versioning][semver].

## [Unreleased]

### Added

- Project scaffolding: gem structure, devcontainer, RSpec, SimpleCov, mutant,
  Sorbet, YARD, RuboCop, lefthook hooks and GitHub Actions.
- `Stweak.version`, which exists so the tooling has a subject to act on until
  the domain provides one.
- The Account domain: the `Account` aggregate, the `AccountCreated` event, the
  `CreateAccount` command and its handler, and the event-sourcing substrate
  they sit on (the `Event`, `Command` and `Aggregate` bases).
- The ports the domain depends on (`EventStore`, `KeyStore`, `PasswordHasher`)
  and the in-memory and crypto adapters that implement them (`InMemoryEventStore`,
  `EncryptingEventStore`, `InMemoryKeyStore`, `Pbkdf2PasswordHasher`,
  `AesGcm`).

[keepachangelog]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
[Unreleased]: https://github.com/rurounijones/stweak/commits/main
