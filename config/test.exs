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
  region: "us-east-1"
