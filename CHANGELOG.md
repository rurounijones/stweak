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
- OpenTelemetry tracing wired into the two drivers, off by default: an unset
  `OTEL_EXPORTER_OTLP_ENDPOINT` disables export, so plain runs and the specs
  emit nothing. OpenObserve added to the compose stack to receive the traces,
  with `bin/` helpers to start it and generate a trace run, and DEVELOP.md
  documents turning it on.
- Tracing spans for the domain and the app-area adapters, added entirely from
  outside the domain: Ruby modules prepended onto `Account`,
  `CreateAccountHandler`, `Aggregate`, the projection system, and every store,
  subscription and hasher, so no file under `lib/` is touched and the domain
  gem gains no telemetry dependency. A small SQLite instrumentation covers the
  one library with no published gem.

[keepachangelog]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
[Unreleased]: https://github.com/rurounijones/stweak/commits/main
