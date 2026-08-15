# Developer guide

How to run everything this project builds and checks.

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

### Driver configuration

The drivers pick their adapters from a single shared `.env` in the drivers
folder. Copy it once:

    cp app/drivers/.env.example app/drivers/.env

Every driver loads that file through `dotenv`, so one edit sets the adapters for
the whole system. Each collaborator has its own selector — `EVENT_STORE`,
`PROJECTION_STORE`, `KEY_STORE`, `SUBSCRIPTION`, `CHECKPOINT_STORE` — naming
`memory` or the real technology and defaulting to the real one; switch them as a
coherent set (all real, or all memory). `dotenv` does not overwrite variables
already set, so the dev container's service endpoints win over the file's
localhost defaults. This is what lets the system be exercised end to end:
generate data with one driver and read it back with another under whichever
adapters the file names. The `.env` itself is git-ignored; `.env.example` is
kept.

### The web admin

`app/drivers/web_admin/` is a read-only Sinatra app that lists accounts from
the projection, shows one account, and lists its events. Like the data
generator it selects its adapters from the shared `app/drivers/.env`; being
read-only it honours the three store selectors and ignores the write-side two.
Run its specs like any other bundle:

    docker compose -f .devcontainer/docker-compose.yml exec dev \
      bash -lc 'cd app/drivers/web_admin && bundle install && bundle exec rspec'

Start it (defaults to the real adapters on port 4567):

    docker compose -f .devcontainer/docker-compose.yml exec dev \
      bash -lc 'cd app/drivers/web_admin && bundle install && bin/web-admin'

It has data to show only after the data generator has run against the same
stores.

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
- **MkDocs** — the docs site. `bundle exec rake doc:site` builds it with the
  Material theme into `site/`. The docs home page lives at `docs/index.md`;
  this guide, the changelog and the license live at the repo root and are
  symlinked into the site from `docs/`; the design decisions, the glossary and
  the topics live directly in `docs/`. Glossary terms show short definitions
  on hover, drawn from `docs/includes/abbreviations.md`.
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

`.github/workflows/pages.yml` publishes the built docs site to GitHub Pages on
every push to main, using the same pinned MkDocs versions as the devcontainer.
