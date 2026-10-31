# ExAwsConfigurator

Hex library that creates and configures SNS topics and SQS queues from the app config,
and publishes/sends messages through them. Domain vocabulary is in [CONTEXT.md](CONTEXT.md).

## Layout

- `lib/`: the library. Only `lib/`, `.formatter.exs`, `mix.exs`, `README*` and `LICENSE*`
  are shipped to Hex (`package/0` in `mix.exs`).
- `test/support/http_stub.ex`: the ExAws http client used by the tests. It forwards to the
  local backend and simulates what that backend can't (`HttpStub.fail/1` for AWS errors).

## Tests

The suite talks to a local SQS/SNS backend (floci, service `localstack` in
`docker-compose.yml`) on `EX_AWS_HOST:EX_AWS_PORT` (default `localhost:4566`). Coverage
must stay at 100% (`coveralls.json`). Minimum Elixir is 1.15 (`mix.exs`) and OTP 26
(README).

## Commits, PRs and releases

- Commit subjects and PR titles use Conventional Commits. PRs are squash-merged, so the
  PR title is what lands on `main`.
- Breaking changes for apps using the library (Elixir/OTP or dependency floor raised,
  public function or config key removed/renamed) need `!`: `fix!:`, `feat!:`. Recheck the
  PR title whenever a breaking commit is added to an open PR.
- Nephila releases from tags (`vX.Y.Z`) with git-cliff. Never hard-code a version in
  `mix.exs` or add a version file, and never pick a version number: `mix.exs` reads it
  from `EX_AWS_CONFIGURATOR_VERSION`, else the tag, else Hex's `hex_metadata.config` (see
  "Where the version comes from" in [RELEASING.md](RELEASING.md)).
- `mix.lock` is not shipped to Hex: bumping a vulnerable dependency there only fixes this
  repo's builds. To force a patched version on consuming apps, raise the floor in `mix.exs`.
