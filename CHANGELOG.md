# CHANGELOG

## [2.0.0](https://github.com/petlove/ex_aws_configurator/compare/v1.4.1...v2.0.0) (2026-04-18)

Full rewrite. No backwards compatibility with 1.x — see the migration section
in the README and the detector in `ExAwsConfigurator.Config` which refuses to
start the app with a v1-shape config and prints a migration guide.

### Features

* **Auto-provisioning on boot.** A supervised one-shot bootstrapper reconciles
  topics, queues, DLQs, policies and subscriptions on every app start. Runs
  idempotently; fails fast if AWS is unreachable or the config is invalid.
* **Declarative config as data.** `topics`, `external_topics` and `queues` are
  flat lists of maps with explicit `:name` — no more atom-keyed nested maps.
* **First-class `external_topics`.** Topics owned by other services are
  declared separately. The library builds their ARN (inferring region and
  account_id from the current AWS identity, or accepting explicit overrides)
  and subscribes local queues to them without trying to create them.
* **Identity resolution via STS.** `:account_id` and `:region` are resolved at
  boot from `sts:GetCallerIdentity` and cached in `:persistent_term`. Config
  no longer needs them.
* **Logical-name publish API.**
  `ExAwsConfigurator.publish(:orders, payload, opts)` and
  `ExAwsConfigurator.send_to_queue(:orders_events, payload, opts)` with
  O(1) ARN/URL lookup from `:persistent_term`. Non-binary payloads are
  auto-encoded with Jason.
* **Batch APIs.** `publish_batch/2` and `send_to_queue_batch/2` accept
  `[%{payload: ..., message_group_id: ..., ...}]` and surface AWS's partial
  successes/failures.
* **FIFO support.** `fifo: true` on a topic or queue appends `.fifo` to the
  AWS name and enforces `:message_group_id` at publish/send time. DLQs
  inherit FIFO-ness from their parent.
* **Custom queue policy.** An optional 1-arity `:policy` function on a queue
  fully replaces the generated SNS → SQS statement when the default is not
  enough.
* **Telemetry.** Four spans emitted:
  `[:ex_aws_configurator, :publish | :send_to_queue | :publish_batch |
  :send_to_queue_batch]`, each with `:start`, `:stop`, `:exception`.
* **`mix ex_aws_configurator.setup`.** Runs the same pipeline standalone for
  use in deploy steps before the app starts.
* **Mox-friendly boundaries.** `Aws.Sns`, `Aws.Sqs` and `Aws.Identity` are
  behaviours — test suites stub them via Mox instead of hitting AWS
  (LocalStack is no longer required).

### Removed

* `ExAwsConfigurator.setup/0` / `setup!/0` — replaced by the supervised
  bootstrapper and the `mix ex_aws_configurator.setup` task.
* `ExAwsConfigurator.get_queue/1`, `get_topic/1` — internal helpers; use
  the Publisher API instead.
* `ExAwsConfigurator.SNS.*`, `ExAwsConfigurator.SQS.*` — collapsed into the
  `Ensure.*` pipeline and `Aws.{Sns,Sqs}` wrappers.
* Per-queue `:prefix`, `:environment`, `:region`, nested `:attributes` and
  `:options`, top-level `:account_id`, `:environment` — see migration guide.
* In-memory URL/ARN cache (`ExAwsConfigurator.Cache`) — superseded by the
  Registry backed by `:persistent_term`.

## [1.4.1](https://github.com/petlove/ex_aws_configurator/compare/v1.4.0...v1.4.1) (2024-09-18)

### Bug Fixes

* returns the actual result for creating aws queues and topics ([#12](https://github.com/petlove/ex_aws_configurator/issues/12)) ([04b915f](https://github.com/petlove/ex_aws_configurator/commit/04b915fedc17b1122e7880f75915d7ac5d164ce5))

## [1.4.0](https://github.com/marciotoze/ex_aws_configurator/compare/v1.3.0...v1.4.0) (2022-03-25)


### Features

* add creation of fifo topics ([4dbc34e](https://github.com/marciotoze/ex_aws_configurator/commit/4dbc34e9f9bdbc8bb41ee0f7f77f1e74562a888f))

## [1.3.0](https://github.com/marciotoze/ex_aws_configurator/compare/v1.2.0...v1.3.0) (2021-10-22)


### Features

* allow content_based_deduplication attributes to be set when creating a queue ([b4c76ff](https://github.com/marciotoze/ex_aws_configurator/commit/b4c76ffedc5c97fe5277872773301d9f2b0951dc))
* allow creation of fifo queues ([ea5818c](https://github.com/marciotoze/ex_aws_configurator/commit/ea5818c5a7db15651f843a16483b0517362ba5e7))


### Bug Fixes

* dead letter queues naming when fifo ([cf7caa8](https://github.com/marciotoze/ex_aws_configurator/commit/cf7caa8321b811730dcc760299bfcc20a365aca0))
* remove fifo attributes when creating standard queues ([544f2d6](https://github.com/marciotoze/ex_aws_configurator/commit/544f2d69ac5bbe48ea76c6e1dcd62c8d37a1c573))

## [1.2.0](https://github.com/marciotoze/ex_aws_configurator/compare/v1.1.2...v1.2.0) (2021-07-30)


### Features

* add raw_message_delivery option to queue ([73e5ce7](https://github.com/marciotoze/ex_aws_configurator/commit/73e5ce7a01928bb11b5154831c82310eaf53ad49))
* Add raw_message_delivery option to queue subscriptions ([904220d](https://github.com/marciotoze/ex_aws_configurator/commit/904220da54808a845596fe429982351e0735e9cf))
* add test case ([3f89cf5](https://github.com/marciotoze/ex_aws_configurator/commit/3f89cf53f9b483542ea2d2e9200941c86a390140))


### Bug Fixes

* build ([f8e4397](https://github.com/marciotoze/ex_aws_configurator/commit/f8e43975e62a6b233bd4bc78074fe2a207a32e3a))

### [1.1.2](https://github.com/marciotoze/ex_aws_configurator/compare/v1.1.1...v1.1.2) (2021-03-29)


### Bug Fixes

* problema when tries to create dead latter queue ([b314f25](https://github.com/marciotoze/ex_aws_configurator/commit/b314f2544709f3fa9b16b3d568c5025e5a92c895))

### [1.1.1](https://github.com/marciotoze/ex_aws_configurator/compare/v1.1.0...v1.1.1) (2021-03-28)


### Bug Fixes

* default aws region to use System env var ([e9ead53](https://github.com/marciotoze/ex_aws_configurator/commit/e9ead53a6438ea147787fdaa30ddda5c9fb81b97))

## [1.1.0](https://github.com/marciotoze/ex_aws_configurator/compare/v1.0.3...v1.1.0) (2021-03-28)


### Features

* add dead letter queue and some minor improvements ([2e8232e](https://github.com/marciotoze/ex_aws_configurator/commit/2e8232e07cd742a6deb1504bb09f4844ca8cd3d1))
* add dead_letter options ([7b66e59](https://github.com/marciotoze/ex_aws_configurator/commit/7b66e59b82126e04986181f3a694d7c086ff9b75))

### [1.0.3](https://github.com/marciotoze/ex_aws_configurator/compare/v1.0.2...v1.0.3) (2021-02-08)


### Bug Fixes

* get ExAws default region in exec time ([c82f932](https://github.com/marciotoze/ex_aws_configurator/commit/c82f932113a399f414988199cbac2934fdabe98a))

### [1.0.2](https://github.com/marciotoze/ex_aws_configurator/compare/v1.0.1...v1.0.2) (2021-02-05)


### Bug Fixes

* default region to get ExAws region ([6bdaa5c](https://github.com/marciotoze/ex_aws_configurator/commit/6bdaa5c881ca93691c756f918c618204f1a8623c))
* flaky test ([0b6c543](https://github.com/marciotoze/ex_aws_configurator/commit/0b6c543fb2e1d6373b2e040b5918afa43a0b8266))

### [1.0.1](https://github.com/marciotoze/ex_aws_configurator/compare/v1.0.0...v1.0.1) (2021-02-05)


### Bug Fixes

* add missing VERSION file to hex ([588eaf0](https://github.com/marciotoze/ex_aws_configurator/commit/588eaf072aa281cce536d676f77b8f3b3b9108d5))

## 1.0.0 (2021-02-05)


### Bug Fixes

* flaky test ([a8df1ae](https://github.com/marciotoze/ex_aws_configurator/commit/a8df1ae06352d579213116e291c3cf95a8bd1da0))
