import Config

config :ex_aws,
  json_codec: Jason,
  access_key_id: "UNSET",
  secret_access_key: "UNSET",
  region: "us-east-1"

config :ex_aws, :sns,
  scheme: "http://",
  host: System.get_env("EX_AWS_HOST", "localhost"),
  port: 4566

config :ex_aws, :sqs,
  scheme: "http://",
  host: System.get_env("EX_AWS_HOST", "localhost"),
  port: 4566

config :ex_aws_sqs, parser: ExAws.SQS.SweetXmlParser

config :logger, :console, format: "$time $metadata[$level] $message\n"

if File.exists?(Path.expand("#{config_env()}.exs", __DIR__)) do
  import_config "#{config_env()}.exs"
end
