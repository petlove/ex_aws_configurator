import Config

config :ex_aws,
  json_codec: Jason

config :ex_aws_sqs, parser: ExAws.SQS.SweetXmlParser

config :logger, :console, format: "$time $metadata[$level] $message\n"

import_config("#{Mix.env()}.exs")
