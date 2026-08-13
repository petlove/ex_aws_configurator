# BASE
FROM hexpm/elixir:1.16.2-erlang-26.2.5.3-debian-bookworm-20260610-slim AS base
ENV MIX_ENV=prod

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix do local.hex --force, local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get

COPY . /app

# DEV
FROM base AS dev

ENV EX_AWS_HOST="localstack"
