# Developer guide

How to run everything this project builds and checks. It is written for a
human starting from a fresh checkout, and it deliberately stays in step with
what CI runs: `.github/workflows/ci.yml` executes the same commands, for the
same reason.

## The environment

Everything runs inside the devcontainer, which is now a compose stack
(`.devcontainer/docker-compose.yml`): the dev container (built from
`.devcontainer/Dockerfile`, where the editor attaches and all the tooling runs)
plus the services the app area's real adapters need — DynamoDB Local, ElasticMQ,
and Redis. SQLite needs no service; it is a file. The host Ruby is deliberately
not used. This is what keeps every machine and CI provably the same.

You need Docker. Bring the stack up once:

    docker compose -f .devcontainer/docker-compose.yml up -d

Run a command inside the dev container like this:

    docker compose -f .devcontainer/docker-compose.yml exec dev \
      bash -lc 'bundle install && bundle exec rake'

The `stweak-bundle` volume holds the installed gems, so `bundle install` is a
no-op after the first run. `bundle exec` matters: the project uses explicit
requires, so the Bundler load path is only applied under it.

## The app area

The domain gem lives at the repo root (`lib/`, `spec/`, its own Gemfile). The
app area is separate: `app/adapters/` holds the real-technology driven
adapters (one bundle, its own Gemfile and specs), and `app/drivers/<name>/`
holds each driving application (each its own bundle). Commands run per bundle:

    docker compose -f .devcontainer/docker-compose.yml exec dev \
      bash -lc 'cd app/adapters && bundle install && bundle exec rspec'
    docker compose -f .devcontainer/docker-compose.yml exec dev \
      bash -lc 'cd app/drivers/data_generator && bundle install && bundle exec rspec'

The adapters reach the services on `localhost` (DynamoDB Local on 8000,
ElasticMQ on 9324, Redis on 6379).

## The checks

### Everything at once

The fast checks, run before every push:

    bundle exec rake

That is `rubocop`, `srb tc`, `spec`, `doc:coverage` and `doc:lint` in order,
and it stops at the first failure.

Mutation testing and the dependency audit are slower on purpose and are left
out of the default task. Run them when the work warrants it:

    bundle exec rake mutant
    bundle exec rake audit

### Each tool

- **RSpec** — the unit tests. `bundle exec rspec`. Coverage is measured on
  every run, reported to `coverage/`, and the suite fails below 100% line and
  branch coverage. The property-based tests written with prop_check run as
  part of this suite.
- **RuboCop** — style and lint. `bundle exec rubocop`.
- **Sorbet** — static typing. `bundle exec srb tc`. Signatures are checked
  before the tests run.
- **YARD** — documentation. `bundle exec rake doc:coverage` requires 100%
  of the public API to be documented; `bundle exec rake doc:lint` runs
  yard-junk over the tags.
- **Markdown** — `markdownlint-cli2` lints the Markdown, prose at 80 columns
  per `.markdownlint-cli2.yaml`.
- **Typos** — `typos` checks prose and identifiers for misspellings.
- **actionlint** — validates the workflow files in `.github/workflows/`.

### The git hooks

`lefthook install` (run in the container) installs the hooks:

- pre-commit, fast and parallel: rubocop and `srb tc` on changed Ruby,
  markdownlint on changed Markdown, typos on everything staged.
- pre-push: the spec suite and `doc:coverage`.

## CI

`.github/workflows/ci.yml` runs the same tooling on every push and pull
request: the specs, the static checks, mutation testing, the dependency audit,
Markdown and typos, and actionlint. The pinned versions there match the
devcontainer's, so what passes locally is what runs in CI.
