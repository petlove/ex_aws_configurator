# ExAwsConfigurator

![GitHub Workflow Status](https://img.shields.io/github/workflow/status/marciotoze/ex_aws_configurator/Elixir%20CI)
[![Codacy Badge](https://api.codacy.com/project/badge/Grade/45e7ca0b984d4ff08d548c9f86899e02)](https://app.codacy.com/gh/marciotoze/ex_aws_configurator?utm_source=github.com&utm_medium=referral&utm_content=marciotoze/ex_aws_configurator&utm_campaign=Badge_Grade_Settings)
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
    {:ex_aws_configurator, "~> 0.1.0"}
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
3. create topic named **prod_another_topic** on defult AWS region (defined by [ExAws](https://github.com/ex-aws/ex_aws))
4. subscribe queue **queue_prefix_an_environment_an_queue** into topic **prefix_an_environment_an_topic**

queue and topic name composition is: `prefix + environment + key` joined by `_`.

| Name | Default | Required | Description |
|------|---------|----------|-------------|
| `account_id` | `nil` | true | your AWS account id, this is used to calculate topic/queue arn |
| `queues` | `[]` | true | list of queues configuration |
| `topics` | `[]` | true | list of topic configuration |
| `environment` | `Mix.env()` | no | current environment, this is used to compose topic/queue name, use `nil` to skip |
| `prefix` | `nil` | no | Used to compose topic/queue name. |
| `region` | `ExAws default` | no | use to specify aws region or to override ex_aws default region |
| `topics` | `[]` | no | list of topics that the queue will subscribe to, must be an atom and the topic must be specified on topics list |

if you prefer more control on **topics** and **queues** criation you can use create/subscribe methods separately

`ExAwsConfigurator.SQS.create_queue(:an_queue)`

`ExAwsConfigurator.SQS.subscribe(:an_topic, :an_queue)`

PS: keys MUST be present on `config.exs` to work correctly.

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
