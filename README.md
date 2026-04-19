# ExAwsConfigurator

[![hex.pm](https://img.shields.io/hexpm/v/ex_aws_configurator.svg)](https://hex.pm/packages/ex_aws_configurator)
[![hex.pm](https://img.shields.io/hexpm/dt/ex_aws_configurator.svg)](https://hex.pm/packages/ex_aws_configurator)
[![hex.pm](https://img.shields.io/hexpm/l/ex_aws_configurator.svg)](https://hex.pm/packages/ex_aws_configurator)

Declarative SNS/SQS provisioning and publishing for Elixir apps. Declare the
topics and queues your service owns (or consumes) in config, and the library
ensures they exist — idempotently — every time the app boots.

- **Auto-provisioning on boot.** Topics, queues, DLQs, policies and
  subscriptions are reconciled against AWS at startup. Fail-fast: if AWS is
  unreachable or the config is invalid, the app does not start.
- **Logical names, not ARNs.** Publishers reference `:orders`, consumers
  reference `:orders_events`. The library resolves ARNs/URLs via AWS STS at
  boot and caches them in `:persistent_term`.
- **First-class external topics.** Topics owned by other services in the same
  account (or cross-account) are declared separately — the library builds
  their ARN and subscribes local queues without trying to create them.
- **FIFO, batch, telemetry.** Built in.

## Installation

```elixir
def deps do
  [
    {:ex_aws_configurator, "~> 2.0"}
  ]
end
```

AWS credentials are resolved through [ExAws](https://github.com/ex-aws/ex_aws)
— set them via env vars or application config:

```elixir
config :ex_aws,
  access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
  secret_access_key: {:system, "AWS_SECRET_ACCESS_KEY"},
  region: {:system, "AWS_REGION"}
```

## Configuration

```elixir
config :ex_aws_configurator,
  queue_prefix: "billing-#{config_env()}",

  # Topics this app owns — will be created.
  topics: [
    %{name: :orders},
    %{name: :payments, fifo: true, content_based_deduplication: true}
  ],

  # Topics owned by other services — NOT created, only referenced.
  external_topics: [
    # Same account: region + account_id default to the current identity.
    %{name: :shipment_updates, prefix: "shipping"},

    # Cross-account / cross-region:
    %{name: :customer_events, prefix: "crm", account_id: "9999", region: "us-west-2"},

    # Fully explicit ARN (escape hatch for anything the template doesn't cover):
    %{name: :partner_feed, arn: "arn:aws:sns:us-east-1:1234:partner-feed"}
  ],

  # Queues this app owns.
  queues: [
    %{
      name: :orders_events,
      subscribe_to: [:orders, :payments, :shipment_updates],
      visibility_timeout: 60,
      message_retention: 1_209_600,
      dlq: true
    }
  ]
```

### Queue options

| Key                         | Default       | Notes                                       |
|-----------------------------|---------------|---------------------------------------------|
| `:name`                     | **required**  | Atom. Used as the logical reference.        |
| `:subscribe_to`             | `[]`          | List of topic names (local or external).    |
| `:fifo`                     | `false`       | Appends `.fifo` to the full AWS name.       |
| `:content_based_deduplication` | `false`    | FIFO only.                                  |
| `:visibility_timeout`       | `60`          | Seconds.                                    |
| `:message_retention`        | `1_209_600`   | 14 days (AWS max).                          |
| `:delay_seconds`            | `0`           |                                             |
| `:maximum_message_size`     | `262_144`     | 256 KB (AWS max).                           |
| `:receive_message_wait_time`| `0`           | Long-polling if set.                        |
| `:raw_message_delivery`     | `false`       | Subscription attribute.                     |
| `:dlq`                      | `true`        | See below.                                  |
| `:policy`                   | `nil`         | Override function. See below.               |

### DLQ

Three forms are accepted:

```elixir
dlq: true                                    # default: max_receive_count 5, 14-day retention
dlq: false                                   # no DLQ
dlq: %{max_receive_count: 10, message_retention: 345_600}
```

The DLQ is always named `<queue_name>_failures` (inherits the parent's
prefix and FIFO-ness).

### Custom policy

By default, each queue's IAM policy grants `sns.amazonaws.com` permission to
`sqs:SendMessage`, guarded by `aws:SourceArn` matching the queue's
`subscribe_to` topics. To override, pass a 1-arity function:

```elixir
%{
  name: :orders_events,
  subscribe_to: [:orders],
  policy: fn %{queue_arn: queue_arn, topic_arns: topic_arns} ->
    %{
      "Version" => "2012-10-17",
      "Statement" => [
        %{
          "Effect" => "Allow",
          "Principal" => %{"Service" => "sns.amazonaws.com"},
          "Action" => "sqs:SendMessage",
          "Resource" => queue_arn,
          "Condition" => %{"ArnEquals" => %{"aws:SourceArn" => topic_arns}}
        },
        %{
          "Effect" => "Allow",
          "Principal" => %{"AWS" => "arn:aws:iam::9999:role/consumer"},
          "Action" => ["sqs:ReceiveMessage", "sqs:DeleteMessage"],
          "Resource" => queue_arn
        }
      ]
    }
  end
}
```

The returned map is the complete policy document — the library no longer
generates its default SNS statement for this queue, so include one yourself if
you want SNS to be able to publish.

## Usage

### Publishing

```elixir
# SNS topic
ExAwsConfigurator.publish(:orders, %{order_id: 42})
# => {:ok, "message-id-..."}

# SQS queue (direct send, no SNS fan-out)
ExAwsConfigurator.send_to_queue(:orders_events, %{order_id: 42})
# => {:ok, "message-id-..."}
```

Binary payloads pass through untouched; anything else is JSON-encoded with
`Jason`.

FIFO topics/queues require `:message_group_id` in `opts`:

```elixir
ExAwsConfigurator.publish(:payments, payload, message_group_id: "customer-42")
```

### Batch

Batch APIs accept a list of entry maps with `:payload` (required) and any
AWS-side attribute:

```elixir
ExAwsConfigurator.publish_batch(:orders, [
  %{payload: %{id: 1}},
  %{payload: %{id: 2}, message_group_id: "g1"}
])
# => {:ok, %{successful: [...], failed: [...]}}

ExAwsConfigurator.send_to_queue_batch(:orders_events, [
  %{payload: %{id: 1}, message_deduplication_id: "dedup-1"}
])
```

AWS batch responses report per-entry success/failure — callers must inspect
both lists.

### Manual setup

The bootstrapper runs automatically when the application starts. To run it
standalone from a shell (e.g. in a deploy step before the app boots):

```sh
mix ex_aws_configurator.setup
```

Or from Elixir — a release hook, a migration-like task, anywhere you need
explicit control:

```elixir
ExAwsConfigurator.setup!()
```

Both paths are idempotent — safe to re-run on every deploy.

### Looking up ARNs and URLs

For routine work use `publish/3` and `send_to_queue/3` — they handle the
lookup, FIFO validation, payload encoding and telemetry in one call. When
you need direct access to a resolved ARN or URL (to hand off to another
library, build a dashboard, wire up a custom subscriber), use the registry:

```elixir
ExAwsConfigurator.Registry.topic_arn!(:orders)
# => "arn:aws:sns:us-east-1:1234:billing-prod_orders"

ExAwsConfigurator.Registry.queue_url!(:orders_events)
# => "https://sqs.us-east-1.amazonaws.com/1234/billing-prod_orders_events"

ExAwsConfigurator.Registry.queue!(:orders_events)
# => %ExAwsConfigurator.Resolved.Queue{arn: ..., url: ..., dlq: ..., ...}
```

### Telemetry

Four spans are emitted (each with `:start`, `:stop`, `:exception`):

- `[:ex_aws_configurator, :publish]`
- `[:ex_aws_configurator, :send_to_queue]`
- `[:ex_aws_configurator, :publish_batch]`
- `[:ex_aws_configurator, :send_to_queue_batch]`

`:stop` metadata carries `:message_id` on success or `:error` on failure.

## Testing

The AWS wrappers (`Aws.Sns`, `Aws.Sqs`) and the identity resolver (`Aws.Identity`)
are behaviours — test code stubs them with [Mox](https://hex.pm/packages/mox)
rather than hitting AWS:

```elixir
# config/test.exs
config :ex_aws_configurator,
  auto_setup: false,
  identity_impl: ExAwsConfigurator.Aws.IdentityMock,
  sns_impl: ExAwsConfigurator.Aws.SnsMock,
  sqs_impl: ExAwsConfigurator.Aws.SqsMock
```

```elixir
# test/test_helper.exs
Mox.defmock(ExAwsConfigurator.Aws.IdentityMock, for: ExAwsConfigurator.Aws.Identity)
Mox.defmock(ExAwsConfigurator.Aws.SnsMock, for: ExAwsConfigurator.Aws.Sns)
Mox.defmock(ExAwsConfigurator.Aws.SqsMock, for: ExAwsConfigurator.Aws.Sqs)

ExUnit.start()
```

`auto_setup: false` stops the bootstrapper from running on app start, so
expectations can be set before any AWS call.

## Migrating from v1.x

v2 is a clean rewrite with no backwards compatibility. See
[UPGRADING.md](UPGRADING.md) for a step-by-step guide: side-by-side config
conversion, option-by-option mapping, default-value differences,
troubleshooting, and a full before/after diff for a typical project.

If v2 detects a v1-shape config, it refuses to start and prints the list of
issues along with the v2 template.

## License

MIT — see below.

Copyright (c) 2014-2020 CargoSense, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
