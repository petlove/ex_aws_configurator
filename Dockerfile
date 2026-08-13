# BASE
FROM elixir:1.10.1-alpine as base
ENV MIX_ENV=prod PORT=80

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

ENV EX_AWS_HOST="localstack"

RUN apk add --update --no-cache curl

# BUILD
FROM base as builder

RUN mix deps.compile

RUN apk add --update --no-cache npm

RUN mix do compile --warnings-as-errors, phx.digest, release
