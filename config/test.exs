import Config

# Tests drive the pipeline explicitly — never auto-run the bootstrapper on app
# start, or the test process would hit AWS before Mox expectations are set.
config :ex_aws_configurator,
  auto_setup: false,
  identity_impl: ExAwsConfigurator.Aws.IdentityMock,
  sns_impl: ExAwsConfigurator.Aws.SnsMock,
  sqs_impl: ExAwsConfigurator.Aws.SqsMock
