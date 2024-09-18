use Mix.Config

config :ex_aws,
  access_key_id: "UNSET",
  secret_access_key: "UNSET",
  security_token: "UNSET"

config :ex_aws, :sns,
  scheme: "http://",
  host: System.get_env("EX_AWS_HOST", "localhost"),
  port: 4566

config :ex_aws, :sqs,
  scheme: "http://",
  host: System.get_env("EX_AWS_HOST", "localhost"),
  port: 4566

config :ex_aws_configurator,
  account_id: "000000000000",
  environment: Mix.env(),
  region: "us-east-1",
  queues: %{
    an_queue: %{
      environment: "test",
      prefix: "prefix",
      region: "us-east-1",
      topics: [:an_topic, :another_topic]
    },
    another_queue: %{
      environment: "test",
      prefix: "prefix",
      region: "us-east-1",
      options: [dead_letter_queue: false],
      topics: []
    }
  },
  topics: %{
    an_topic: %{environment: "test", prefix: "prefix"},
    another_topic: %{environment: nil, region: "sa-east-1"}
  }
