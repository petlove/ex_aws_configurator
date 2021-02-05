use Mix.Config

config :ex_aws,
  access_key_id: "UNSET",
  secret_access_key: "UNSET",
  region: "us-east-1"

config :ex_aws, :sns,
  scheme: "http://",
  host: "localhost",
  port: 4566

config :ex_aws, :sqs,
  scheme: "http://",
  host: "localhost",
  port: 4566

config :ex_aws_configurator,
  account_id: "000000000000",
  queues: %{
    an_queue: %{
      environment: "test",
      prefix: "prefix",
      region: "us-east-1",
      topics: [:an_topic, :another_topic]
    },
    xxx: %{
      environment: "test",
      prefix: "prefix",
      region: "us-east-1",
      topics: []
    }
  },
  topics: %{
    an_topic: %{environment: "test", prefix: "prefix", region: "us-east-1"},
    another_topic: %{environment: "teste", prefix: "prefixo", region: "sa-east-1"}
  }
