use Mix.Config

config :ex_aws_configurator,
  environment: Mix.env(),
  region: System.get_env("AWS_REGION")
