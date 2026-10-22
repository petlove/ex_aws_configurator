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
