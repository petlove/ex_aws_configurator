# Upgrading from 1.4.x to 2.0

v2 is a ground-up rewrite. There is no shim, no compat layer, and the v2
`Config` module refuses to start the app if it detects v1-shape config —
so upgrading is an explicit, one-shot migration.

This guide walks through:

1. [What changed and why](#what-changed-and-why)
2. [Config: side-by-side conversion](#config-side-by-side-conversion)
3. [API: call translation](#api-call-translation)
4. [Option-by-option mapping](#option-by-option-mapping)
5. [Default-value differences to watch for](#default-value-differences-to-watch-for)
6. [Behaviour changes at boot and deploy](#behaviour-changes-at-boot-and-deploy)
7. [Testing: goodbye LocalStack, hello Mox](#testing-goodbye-localstack-hello-mox)
8. [Minimal diff example](#minimal-diff-example)
9. [Full-featured example](#full-featured-example)

---

## What changed and why

| Area | v1.4.x | v2.0 |
|---|---|---|
| Config shape | Atom-keyed maps of maps | Flat lists of maps with explicit `:name` |
| Identity (`account_id`, `region`) | Declared in config | Resolved at boot via `sts:GetCallerIdentity` |
| Prefix/environment | Declared per-resource | Single global `:queue_prefix` |
| External (cross-service) topics | No distinction from local | First-class `:external_topics` |
| Setup | Manual `ExAwsConfigurator.setup/0` | Automatic on app start + `mix ex_aws_configurator.setup` |
| URL/ARN cache | In-memory `Cache` (ETS-like) | `:persistent_term`, populated once at boot |
| SNS/SQS boundary | Direct `ExAws` calls | Behaviours (`Aws.Sns`, `Aws.Sqs`) — mockable |
| Testing | LocalStack | Mox |
| Publish API | `ExAwsConfigurator.SNS.publish/3` | `ExAwsConfigurator.publish/3` |

The driving motivation was a declarative model that's safe to re-apply on
every deploy, separates "I own this resource" from "I only consume it", and
can be fully unit-tested without LocalStack (which is no longer free).

---

## Config: side-by-side conversion

### v1.4.x

```elixir
config :ex_aws_configurator,
  account_id: "000000000000",
  environment: "production",
  region: "us-east-1",
  queues: %{
    orders_events: %{
      environment: "production",
      prefix: "billing",
      region: "us-east-1",
      topics: [:orders, :payments],
      attributes: [
        visibility_timeout: 60,
        message_retention_period: 1_209_600
      ],
      options: [
        max_receive_count: 7,
        dead_letter_queue: true,
        dead_letter_queue_suffix: "_failures",
        raw_message_delivery: false
      ]
    }
  },
  topics: %{
    orders: %{environment: "production", prefix: "billing", region: "us-east-1"},
    payments: %{environment: "production", prefix: "billing", region: "us-east-1"}
  }
```

Full AWS name in v1: `"<prefix>_<environment>_<key>"` — e.g. `billing_production_orders_events`.

### Equivalent v2.0

```elixir
config :ex_aws_configurator,
  queue_prefix: "billing_production",

  topics: [
    %{name: :orders},
    %{name: :payments}
  ],

  queues: [
    %{
      name: :orders_events,
      subscribe_to: [:orders, :payments],
      visibility_timeout: 60,
      message_retention: 1_209_600,
      dlq: %{max_receive_count: 7}
    }
  ]
```

Full AWS name in v2: `"<queue_prefix>_<name>"` — e.g. `billing_production_orders_events`.
**This matches v1 exactly** as long as `queue_prefix` is set to
`"<v1_prefix>_<v1_environment>"`.

Things to notice:

- `:account_id` and `:region` are gone. STS resolves them at boot.
- `:environment` is gone. Fold it into `:queue_prefix` if you want the same
  naming.
- `topics`/`queues` are lists, not maps. Each entry has an explicit `:name`.
- Queue's `:topics` → `:subscribe_to`.
- `:attributes` and `:options` are flattened onto the queue map.
- DLQ: `:dlq` is a single key (`true` | `false` | `%{...}`). No more
  `dead_letter_queue: true` + `dead_letter_queue_suffix: "_failures"` split.
  Defaults match v1's `_failures` suffix; only `max_receive_count` default
  changed (v1: 7 → v2: 5), so set `dlq: %{max_receive_count: 7}` to keep
  bit-for-bit behaviour.

---

## API: call translation

| Purpose | v1.4.x | v2.0 |
|---|---|---|
| Provision on demand | `ExAwsConfigurator.setup()` / `setup!()` | Automatic on app start, or call `ExAwsConfigurator.setup!/0` from code |
| Provision in a deploy step | `mix run -e 'ExAwsConfigurator.setup!()'` | `mix ex_aws_configurator.setup` |
| Publish to a topic | `ExAwsConfigurator.SNS.publish(:orders, payload, opts)` | `ExAwsConfigurator.publish(:orders, payload, opts)` |
| Send to a queue | `ExAwsConfigurator.SQS.send_message(:orders_events, payload, opts)` | `ExAwsConfigurator.send_to_queue(:orders_events, payload, opts)` |
| Create a topic manually | `ExAwsConfigurator.SNS.create_topic(:orders)` | Not needed — bootstrapper handles it |
| Create a queue manually | `ExAwsConfigurator.SQS.create_queue(:orders_events)` | Not needed — bootstrapper handles it |
| Subscribe queue to topic | `ExAwsConfigurator.SQS.subscribe(:orders, :orders_events)` | Declare in config `:subscribe_to`; bootstrapper handles it |
| Look up a queue's URL / ARN | `ExAwsConfigurator.get_queue(:orders_events)` | `ExAwsConfigurator.Registry.queue_url!/1` / `queue_arn!/1` / `queue!/1` |
| Look up a topic's ARN | `ExAwsConfigurator.get_topic(:orders)` | `ExAwsConfigurator.Registry.topic_arn!/1` |
| Batch publish | not available | `ExAwsConfigurator.publish_batch(:orders, entries)` |
| Batch send | not available | `ExAwsConfigurator.send_to_queue_batch(:queue, entries)` |

### Payload differences

v1 accepted any serializable term and let `ExAws` handle encoding. v2
explicitly:

- passes **binaries** through untouched,
- **JSON-encodes anything else** with `Jason.encode!/1`.

If your code was passing maps expecting Jason encoding, it keeps working.
If your code was pre-encoding to JSON strings, it also keeps working.

### FIFO

v1 enforced `:message_group_id` only via AWS's error response. v2 validates
**at the call site** and raises `ArgumentError`:

```elixir
# v2: raises immediately
ExAwsConfigurator.publish(:orders_fifo, payload)

# v2: OK
ExAwsConfigurator.publish(:orders_fifo, payload, message_group_id: "customer-42")
```

This is usually a bug-fix for apps that had silent drops on FIFO topics.

---

## Option-by-option mapping

### Top-level

| v1 key | v2 equivalent |
|---|---|
| `:account_id` | Removed — resolved via STS |
| `:region` | Removed — resolved via STS/ExAws |
| `:environment` | Fold into `:queue_prefix` |
| `:topics` (map) | `:topics` (list of maps) |
| `:queues` (map) | `:queues` (list of maps) |

### Topic

| v1 key (under each topic map) | v2 equivalent |
|---|---|
| `:prefix` | Covered by global `:queue_prefix` |
| `:environment` | Covered by global `:queue_prefix` |
| `:region` | Removed — single region per app |
| `:attributes` (keyword list) | Flattened onto the topic map: `:fifo`, `:content_based_deduplication` |

### Queue

| v1 key | v2 equivalent |
|---|---|
| `:prefix`, `:environment`, `:region` | Global `:queue_prefix` |
| `:topics` | `:subscribe_to` |
| `:attributes.visibility_timeout` | `:visibility_timeout` |
| `:attributes.message_retention_period` | `:message_retention` |
| `:attributes.delay_seconds` | `:delay_seconds` |
| `:attributes.maximum_message_size` | `:maximum_message_size` |
| `:attributes.receive_message_wait_time_seconds` | `:receive_message_wait_time` |
| `:attributes.fifo_queue` | `:fifo` |
| `:attributes.content_based_deduplication` | `:content_based_deduplication` |
| `:options.max_receive_count` | `:dlq.max_receive_count` (`:dlq` as map) |
| `:options.dead_letter_queue` | `:dlq` as `true`/`false` |
| `:options.dead_letter_queue_suffix` | `:dlq.suffix` (default `"_failures"` — same as v1) |
| `:options.raw_message_delivery` | `:raw_message_delivery` |

### New in v2 (no v1 equivalent)

- `:external_topics` — declare topics owned by other services.
- Queue `:policy` — 1-arity function returning the full IAM policy document.
- Batch APIs + telemetry spans.

---

## Default-value differences to watch for

Most defaults are preserved. The one behavioural change:

| Key | v1 default | v2 default |
|---|---|---|
| `max_receive_count` (DLQ redrive) | `7` | `5` |

If you relied on the v1 default without setting it, messages will now move to
the DLQ after 5 failed receives instead of 7. Either accept it (usually the
better default) or set `dlq: %{max_receive_count: 7}` explicitly on the
queues that need the old behaviour.

Everything else (`visibility_timeout: 60`, `message_retention: 1_209_600`,
DLQ suffix `_failures`, etc.) matches v1.

---

## Behaviour changes at boot and deploy

### Before (v1)

Provisioning was explicit: you called `ExAwsConfigurator.setup!()` in a
release hook, CI step, or `Application.start/2` callback. Forgetting it
meant your app started but publishes silently failed (no subscription, no
policy, nothing).

### After (v2)

The bootstrapper runs **automatically** on app start as a supervisor child.
It:

1. Loads and validates the config (crash on any problem).
2. Resolves the AWS identity (crash if STS unreachable).
3. Reconciles topics → DLQs → queues → subscriptions.
4. Populates the runtime lookup table.

If any step fails, the app supervisor fails to start. This is intentional:
an app whose queues aren't set up is not a healthy app.

If you prefer to run provisioning **before** the app starts (e.g. a CI job
or a pre-deploy hook), use:

```sh
mix ex_aws_configurator.setup
```

…and optionally disable auto-boot in that environment:

```elixir
config :ex_aws_configurator, auto_setup: false
```

### When to disable `auto_setup`

- **Test environment**: required. Mox expectations won't be set yet when the
  app starts.
- **Ephemeral tooling** that only needs to publish, not provision.
- **Deployments that split provisioning and app start** into separate steps.

---

## Testing: goodbye LocalStack, hello Mox

v1 test suites typically relied on LocalStack + docker-compose. LocalStack's
free tier was limited and the project went paid for many services, so v2 is
designed to be tested entirely in-process.

All AWS calls go through behaviours:

- `ExAwsConfigurator.Aws.Sns`
- `ExAwsConfigurator.Aws.Sqs`
- `ExAwsConfigurator.Aws.Identity`

### `test/test_helper.exs`

```elixir
Mox.defmock(ExAwsConfigurator.Aws.IdentityMock, for: ExAwsConfigurator.Aws.Identity)
Mox.defmock(ExAwsConfigurator.Aws.SnsMock, for: ExAwsConfigurator.Aws.Sns)
Mox.defmock(ExAwsConfigurator.Aws.SqsMock, for: ExAwsConfigurator.Aws.Sqs)

ExUnit.start()
```

### `config/test.exs`

```elixir
config :ex_aws_configurator,
  auto_setup: false,
  identity_impl: ExAwsConfigurator.Aws.IdentityMock,
  sns_impl: ExAwsConfigurator.Aws.SnsMock,
  sqs_impl: ExAwsConfigurator.Aws.SqsMock
```

### In tests

```elixir
import Mox

setup :verify_on_exit!

test "publishes an order" do
  expect(SnsMock, :publish, fn _arn, message, _opts ->
    assert message =~ "order_id"
    {:ok, "msg-1"}
  end)

  assert {:ok, "msg-1"} = MyApp.place_order(%{order_id: 1})
end
```

No Docker required.

---

## Minimal diff example

Say your v1 config looked like this:

```elixir
# v1 — config/runtime.exs
config :ex_aws_configurator,
  account_id: System.fetch_env!("AWS_ACCOUNT_ID"),
  environment: System.fetch_env!("APP_ENV"),
  region: "us-east-1",
  topics: %{
    orders: %{prefix: "billing"},
    payments: %{prefix: "billing"}
  },
  queues: %{
    orders_events: %{
      prefix: "billing",
      topics: [:orders, :payments],
      attributes: [visibility_timeout: 30],
      options: [max_receive_count: 7, dead_letter_queue: true]
    }
  }
```

And your `application.ex`:

```elixir
def start(_, _) do
  ExAwsConfigurator.setup!()

  children = [MyApp.Worker]
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

And somewhere in your code:

```elixir
ExAwsConfigurator.SNS.publish(:orders, %{order_id: id})
ExAwsConfigurator.SQS.send_message(:orders_events, %{order_id: id})
```

### v2 equivalent

```elixir
# v2 — config/runtime.exs
config :ex_aws_configurator,
  queue_prefix: "billing_#{System.fetch_env!("APP_ENV")}",
  topics: [
    %{name: :orders},
    %{name: :payments}
  ],
  queues: [
    %{
      name: :orders_events,
      subscribe_to: [:orders, :payments],
      visibility_timeout: 30,
      dlq: %{max_receive_count: 7}
    }
  ]
```

`application.ex` — just remove the `setup!` call. The bootstrapper is a
child of the `:ex_aws_configurator` app supervisor now, so it runs
automatically as long as your `mix.exs` lists the dep (which it did).

```elixir
def start(_, _) do
  children = [MyApp.Worker]
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

Publish sites:

```elixir
# old
ExAwsConfigurator.SNS.publish(:orders, %{order_id: id})
ExAwsConfigurator.SQS.send_message(:orders_events, %{order_id: id})

# new
ExAwsConfigurator.publish(:orders, %{order_id: id})
ExAwsConfigurator.send_to_queue(:orders_events, %{order_id: id})
```

That's the whole migration for a typical project.

---

## Full-featured example

A more realistic setup — multiple queues including FIFO, DLQ tuning per
queue, `raw_message_delivery`, custom attributes, and a topic owned by
another service (which in v1 had to be created locally or provisioned out
of band, and in v2 gets a dedicated `:external_topics` section).

### v1.4.x

```elixir
# config/runtime.exs
env = System.fetch_env!("APP_ENV")

config :ex_aws_configurator,
  account_id: System.fetch_env!("AWS_ACCOUNT_ID"),
  environment: env,
  region: "us-east-1",

  topics: %{
    orders: %{
      environment: env,
      prefix: "billing",
      region: "us-east-1"
    },
    payments: %{
      environment: env,
      prefix: "billing",
      region: "us-east-1",
      attributes: [
        fifo_topic: true,
        content_based_deduplication: true
      ]
    },
    # The shipping service owns this topic, but we publish creation from here
    # because v1 has no way to say "don't create, just reference".
    shipment_updates: %{
      environment: env,
      prefix: "shipping",
      region: "us-east-1"
    }
  },

  queues: %{
    orders_events: %{
      environment: env,
      prefix: "billing",
      region: "us-east-1",
      topics: [:orders, :shipment_updates],
      attributes: [
        visibility_timeout: 45,
        message_retention_period: 345_600,
        delay_seconds: 0,
        maximum_message_size: 262_144,
        receive_message_wait_time_seconds: 20
      ],
      options: [
        max_receive_count: 7,
        dead_letter_queue: true,
        dead_letter_queue_suffix: "_failures",
        raw_message_delivery: true
      ]
    },

    payments_events: %{
      environment: env,
      prefix: "billing",
      region: "us-east-1",
      topics: [:payments],
      attributes: [
        fifo_queue: true,
        content_based_deduplication: true,
        visibility_timeout: 60,
        message_retention_period: 1_209_600
      ],
      options: [
        max_receive_count: 3,
        dead_letter_queue: true,
        dead_letter_queue_suffix: "_failures"
      ]
    },

    # Lightweight queue, no DLQ, short visibility.
    audit_log: %{
      environment: env,
      prefix: "billing",
      region: "us-east-1",
      topics: [:orders, :payments],
      attributes: [
        visibility_timeout: 10,
        message_retention_period: 86_400
      ],
      options: [
        dead_letter_queue: false
      ]
    }
  }
```

### Equivalent v2.0

```elixir
# config/runtime.exs
config :ex_aws_configurator,
  queue_prefix: "billing_#{System.fetch_env!("APP_ENV")}",

  topics: [
    %{name: :orders},
    %{name: :payments, fifo: true, content_based_deduplication: true}
  ],

  # Topics owned by other services — referenced, not created.
  external_topics: [
    %{name: :shipment_updates, prefix: "shipping"}
  ],

  queues: [
    %{
      name: :orders_events,
      subscribe_to: [:orders, :shipment_updates],
      visibility_timeout: 45,
      message_retention: 345_600,
      receive_message_wait_time: 20,
      raw_message_delivery: true,
      dlq: %{max_receive_count: 7}
    },

    %{
      name: :payments_events,
      subscribe_to: [:payments],
      fifo: true,
      content_based_deduplication: true,
      visibility_timeout: 60,
      dlq: %{max_receive_count: 3}
    },

    %{
      name: :audit_log,
      subscribe_to: [:orders, :payments],
      visibility_timeout: 10,
      message_retention: 86_400,
      dlq: false
    }
  ]
```

Notes on this migration:

- **`shipment_updates`** moved from `:topics` to `:external_topics`. In v1
  it would have been created locally (duplicating what the shipping service
  already owns). In v2 it stays in the shipping account/service and
  `orders_events` just subscribes to the existing ARN.
- **`payments_events`** keeps FIFO + `content_based_deduplication`, and
  because the parent is FIFO its auto-generated DLQ
  (`billing_<env>_payments_events_failures.fifo`) is FIFO too — v2 infers
  this, you don't need to set it manually.
- **`audit_log`** drops the DLQ cleanly with `dlq: false` — in v1 that was
  `options: [dead_letter_queue: false]`.
- **`delay_seconds: 0`** and **`maximum_message_size: 262_144`** were
  explicitly written in v1 but they match v2 defaults — omit them in v2.
- **`dead_letter_queue_suffix: "_failures"`** is the v1 *and* v2 default,
  so it disappears from config entirely.
- **`max_receive_count: 7`** was the v1 default but v2 defaults to `5`, so
  it has to be written explicitly for queues that want the old behaviour.

At the call site, FIFO publishes now require `:message_group_id`:

```elixir
ExAwsConfigurator.publish(:payments, payload, message_group_id: customer_id)
ExAwsConfigurator.send_to_queue(:payments_events, payload, message_group_id: customer_id)
```

---

## Troubleshooting

**App crashes on boot with `ex_aws_configurator v2 detected v1.x-style configuration`.**
The detector found a strong v1 signal (map-shaped topics/queues, top-level
`:account_id`, nested `:attributes`/`:options`, …). The error lists every
signal it found and includes the v2 template. Work through them one by one.

**App crashes on boot with `failed to resolve AWS identity via STS`.**
v2 calls `sts:GetCallerIdentity` at boot. Make sure the role or credentials
the app runs with have `sts:GetCallerIdentity` allowed (it's in the default
permission set for nearly every role, but locked-down roles may not have it).

**`ArgumentError: FIFO :orders_fifo requires :message_group_id in opts`.**
v2 validates FIFO at the call site — you were probably relying on AWS's
error to surface this before. Add `:message_group_id` to the opts, or make
the publish site handle the `ArgumentError`.

**DLQ messages are piling up faster than before.**
`max_receive_count` default went from 7 to 5. Set `dlq: %{max_receive_count: 7}`
to restore v1 behaviour.
