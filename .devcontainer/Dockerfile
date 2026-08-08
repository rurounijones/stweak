FROM ruby:4.0-slim-trixie

# Build tooling for native gem extensions, git for tooling that shells out to
# it (lefthook, mutant's --since), and the small conveniences that make an
# interactive shell in here bearable.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    less \
    pkg-config \
  && rm -rf /var/lib/apt/lists/*

# Node is only here for markdownlint-cli2, which has no Ruby equivalent worth
# the trade.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# markdownlint-cli2, for the Markdown linting the pre-commit hook runs. Pinned
# like the tools below, since Node resolves it separately from any lockfile.
ARG MARKDOWNLINT_CLI2_VERSION=0.23.2
RUN npm install --global --no-audit --no-fund \
  "markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION}"

# typos-cli, for spelling in prose and identifiers.
ARG TYPOS_VERSION=1.49.0
RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  case "$arch" in \
    arm64) target='aarch64-unknown-linux-musl' ;; \
    amd64) target='x86_64-unknown-linux-musl' ;; \
    *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
  esac; \
  curl -fsSL "https://github.com/crate-ci/typos/releases/download/v${TYPOS_VERSION}/typos-v${TYPOS_VERSION}-${target}.tar.gz" \
    | tar -xz -C /usr/local/bin ./typos

# actionlint, for validating the workflow file without pushing it.
ARG ACTIONLINT_VERSION=1.7.12
RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${arch}.tar.gz" \
    | tar -xz -C /usr/local/bin actionlint

# lefthook, for the git hooks.
ARG LEFTHOOK_VERSION=2.1.10
RUN set -eux; \
  arch="$(dpkg --print-architecture)"; \
  curl -fsSL -o /tmp/lefthook.deb \
    "https://github.com/evilmartians/lefthook/releases/download/v${LEFTHOOK_VERSION}/lefthook_${LEFTHOOK_VERSION}_${arch}.deb"; \
  dpkg -i /tmp/lefthook.deb; \
  rm /tmp/lefthook.deb

# Bundler writes here, and devcontainer.json mounts a named volume over it so
# installed gems survive a rebuild without ever touching the host.
ENV BUNDLE_PATH=/usr/local/bundle
ENV BUNDLE_JOBS=4

WORKDIR /workspaces/stweak
