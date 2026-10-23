# ExAwsConfigurator

![GitHub Workflow Status](https://img.shields.io/github/workflow/status/marciotoze/ex_aws_configurator/Elixir%20CI)
[![Coverage Status](https://coveralls.io/repos/github/marciotoze/ex_aws_configurator/badge.svg?branch=main)](https://coveralls.io/github/marciotoze/ex_aws_configurator?branch=main)
[![hex.pm](https://img.shields.io/hexpm/v/ex_aws_configurator.svg)](https://hex.pm/packages/ex_aws)
[![hex.pm](https://img.shields.io/hexpm/dt/ex_aws_configurator.svg)](https://hex.pm/packages/ex_aws)
[![hex.pm](https://img.shields.io/hexpm/l/ex_aws_configurator.svg)](https://hex.pm/packages/ex_aws)

Simple json based configurator for AWS SNS/SQS services, use to setup your topics and queues or/and to help to handle topics and queues with prefix or environment based name.

check our [documentation](https://hexdocs.pm/ex_aws_configurator/api-reference.html)

## Installation

The package can be installed by adding jason to your list of dependencies in mix.exs:

```elixir
def deps do
  [
    {:ex_aws_configurator, "~> 2.0"}
  ]
end
```

#### Configuring ExAws

that package use [ExAws](https://github.com/ex-aws/ex_aws) to make requests to AWS, you will must to set ex_aws configuration into your config file to:

```elixir
config :ex_aws,
  access_key_id: "<AWS_ACCESS_KEY_ID>",
  secret_access_key: "<AWS_SECRET_ACCESS_KEY>"
```

alternatively, you can set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` on your system environment, see [ExAws](https://github.com/ex-aws/ex_aws) for more.

#### Configuring ExAwsConfigurator

look for the `config.exs` example above:

```elixir
config :ex_aws_configurator,
  account_id: "000000000000",
  queues: %{
    an_queue: %{
      environment: "an_environment",
      prefix: "queue_prefix",
      region: "us-east-1",
      topics: [:an_topic]
    },
    # ...
  },
  topics: %{
    an_topic: %{environment: "an_environment", prefix: "prefix", region: "us-east-1"},
    another_topic: %{},
    # ...
  }
```

assuming `prod` environment, when run `ExAwsConfigurator.setup()` will:

1. create queue named **queue_prefix_an_environment_an_queue** on **us-east-1** AWS region
2. create topic named **prefix_an_environment_an_topic** on **us-east-1** AWS region
3. create topic named **prod_another_topic** on default AWS region
4. subscribe queue **queue_prefix_an_environment_an_queue** into topic **prefix_an_environment_an_topic**

queue and topic name composition is: `prefix + environment + key` joined by `_`.

| Name | Default | Required | Description |
|------|---------|----------|-------------|
| `account_id` | `nil` | true | your AWS account id, this is used to calculate topic/queue arn |
| `queues` | `[]` | true | list of queues configuration |
| `topics` | `[]` | true | list of topic configuration |
| `environment` | `Mix.env()` | no | current environment, this is used to compose topic/queue name, use `nil` to skip |
| `prefix` | `nil` | no | Used to compose topic/queue name. |
| `region` | `System.get_env("AWS_REGION")` | no | use to specify aws region or to override ex_aws default region |
| `topics` | `[]` | no | list of topics that the queue will subscribe to, must be an atom and the topic must be specified on topics list |

`ExAwsConfigurator.setup()` is idempotent: topics and queues that already exist have their mutable attributes (policy, redrive policy, timeouts...) updated to match the configuration, so it is safe to run it on every deploy. It never deletes anything.

#### External accounts (topics owned by other AWS accounts)

To subscribe a queue to a topic that belongs to another AWS account (another business unit, for example), declare the account under `accounts` and reference it from the topic:

```elixir
config :ex_aws_configurator,
  account_id: System.get_env("AWS_ACCOUNT_ID"),   # the default account
  region: "sa-east-1",
  accounts: %{
    health: %{id: System.get_env("AWS_HEALTH_ACCOUNT_ID"), region: "sa-east-1"}
  },
  topics: %{
    subscription_activated: %{prefix: "health_api", account: :health},
    pet_plan_canceled: %{prefix: "health_backoffice", account: :health, on_unauthorized: :warn},
    legacy_topic: %{arn: "arn:aws:sns:sa-east-1:111111111111:some-name-outside-our-convention"}
  },
  queues: %{
    traits_health_plan: %{prefix: "my_app", topics: [:subscription_activated, :pet_plan_canceled]}
  }
```

- a topic whose account differs from the default one is **external**: its ARN is composed as usual (`prefix + environment + key` on the account region), the queue policy allows it as a source, but `setup/0` never tries to create it, since it is managed by its owner;
- `arn` declares a topic by its raw ARN, skipping name composition; the account and region come from the ARN;
- `setup/0` subscribes the queue to the external topic, which only works when the topic owner allows `sns:Subscribe` from your account. If it is denied the setup fails (`{:error, :subscriptions}`). Set `on_unauthorized: :warn` on the topic (or globally with `config :ex_aws_configurator, on_unauthorized: :warn`) to only log a warning instead; the warning contains the policy statement the owner must add.

Account options:

| Name | Default | Required | Description |
|------|---------|----------|-------------|
| `id` | `nil` | true | the AWS account id; accepts `{:system, "ENV_VAR"}` |
| `region` | global `region` | no | region where the account resources live |

Besides `account_id`, `region`, `environment`, `prefix`, `separator` and `attributes`, topics accept:

| Name | Default | Required | Description |
|------|---------|----------|-------------|
| `account` | `:default` | no | name of the account (declared in `accounts`) that owns the topic |
| `arn` | `nil` | no | raw topic ARN; replaces name composition, `account` and `region` |
| `on_unauthorized` | global `on_unauthorized` (`:error`) | no | `:error` or `:warn`, what to do when the owner of an external topic refuses the subscription |

`ExAwsConfigurator.setup/0` needs, besides the create permissions, `sqs:GetQueueUrl`, `sqs:SetQueueAttributes`, `sqs:TagQueue`, `sns:GetTopicAttributes` and `sns:SetTopicAttributes` on your own account.

#### Upgrading from 1.x

- `setup/0` updates existing topics and queues instead of failing when their attributes changed. **Attributes edited by hand on AWS (a queue policy, for example) are overwritten by what the configuration declares**: move any manual adjustment into the configuration (such as an external account) before upgrading;
- `setup/0` now fails with `{:error, :subscriptions}` when a subscription cannot be created (before, subscription errors were ignored);
- `setup/0` needs new IAM permissions: `sqs:GetQueueUrl`, `sqs:SetQueueAttributes`, `sqs:TagQueue`, `sns:GetTopicAttributes` and `sns:SetTopicAttributes`;
- `ExAwsConfigurator.SNS.publish/3` accepts `opts` forwarded to `ExAws.SNS.publish/2` (for example `message_attributes`). Binaries are published as they are instead of being JSON encoded; maps and lists are still JSON encoded;
- the raw message delivery attribute of a subscription is now set on the topic region;
- `ExAwsConfigurator.get_env/1`, `ExAwsConfigurator.Queue.account_id/1`, `ExAwsConfigurator.Topic.account_id/1` and `ExAwsConfigurator.Config.default_account/0` were removed. `ExAwsConfigurator.Config` is the only module that reads the application env, and every `%Queue{}`/`%Topic{}` it builds carries its `%Account{}`, so `Queue.arn/1`, `Queue.url/1` and `Topic.arn/1` no longer fall back to the global `account_id`. Use `ExAwsConfigurator.get_account(:default)` for the default account;
- the global `region`, `environment` and `on_unauthorized` keys accept `{:system, "ENV_VAR"}`, like `account_id` already did;
- when the dead letter queue of a queue cannot be created or updated, `ExAwsConfigurator.SQS.create_queue/2` now returns that error without touching the queue itself (before, the queue was created anyway, with a redrive policy pointing to a missing dead letter queue). The dead letter queue is available as `ExAwsConfigurator.Queue.dead_letter_queue/1` and the redrive policy as `ExAwsConfigurator.Queue.redrive_policy/1`, already set on the `%Queue{}` returned by `get_queue/1`;
- `ExAwsConfigurator.setup/0` resolves and validates the whole configuration (`ExAwsConfigurator.Config.load/0`) before touching AWS: a queue subscribed to a topic that is not configured, an account without `id` or an invalid `arn` now raise before anything is created.

if you prefer more control on **topics** and **queues** creation you can use the create/subscribe functions separately

```elixir
ExAwsConfigurator.SNS.create_topic(:an_topic)
ExAwsConfigurator.SQS.create_queue(:an_queue)
ExAwsConfigurator.SQS.subscribe(:an_queue, :an_topic)
```

Every function of `ExAwsConfigurator.SNS` and `ExAwsConfigurator.SQS` accepts either the atom that names the resource in the configuration (the key MUST be present on `config.exs`) or the `%ExAwsConfigurator.Topic{}`/`%ExAwsConfigurator.Queue{}` struct itself, which is handy to drive the adapters from a struct you built or fetched once:

```elixir
queue = ExAwsConfigurator.get_queue(:an_queue)

ExAwsConfigurator.SQS.create_queue(queue)
for topic <- queue.topics, do: ExAwsConfigurator.SQS.subscribe(queue, topic)
```

this package provide some helpers to **publish** or **send message** too, for complete use please, check our [documentation](https://hexdocs.pm/ex_aws_configurator/api-reference.html)

## Contributing

feel free to contribute, issues and pull requests are welcome

## License

The MIT License (MIT)

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
