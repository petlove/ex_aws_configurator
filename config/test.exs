import Config

ex_aws_host = System.get_env("EX_AWS_HOST", "localhost")
ex_aws_port = String.to_integer(System.get_env("EX_AWS_PORT", "4566"))

config :ex_aws,
  access_key_id: "UNSET",
  secret_access_key: "UNSET",
  region: "us-east-1",
  # Forwards to the local backend and simulates AWS name validation and an external
  # account that refuses sns:Subscribe (see test/support/http_stub.ex).
  http_client: ExAwsConfigurator.HttpStub

config :ex_aws, :sns,
  scheme: "http://",
  host: ex_aws_host,
  port: ex_aws_port

config :ex_aws, :sqs,
  scheme: "http://",
  host: ex_aws_host,
  port: ex_aws_port

config :ex_aws_configurator,
  account_id: "000000000000",
  region: "us-east-1"

# Resources used by the atom form of the adapters (`SNS.publish(:an_topic, ...)`) and by
# `setup/0`. They are created on the local backend by the suite.
config :ex_aws_configurator,
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
