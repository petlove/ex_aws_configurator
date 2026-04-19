# BASE
FROM hexpm/elixir:1.18.3-erlang-27.2-alpine-3.21.0 AS base
ENV MIX_ENV=prod

RUN apk add --update --no-cache \
  bash \
  git \
  build-base \
  tzdata

WORKDIR /app
COPY . /app

RUN mix do local.hex --force, local.rebar --force, deps.get

# DEV
FROM base AS dev

ENV MIX_ENV=dev EX_AWS_HOST="moto"

RUN apk add --update --no-cache curl

# TEST
FROM base AS test
ENV MIX_ENV=test

RUN mix deps.compile
RUN mix compile --warnings-as-errors

CMD ["/app/ci/test.sh"]

# BUILD
FROM base AS builder

RUN mix deps.compile
RUN apk add --update --no-cache npm
RUN mix compile --warnings-as-errors
