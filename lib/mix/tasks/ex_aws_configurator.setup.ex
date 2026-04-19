defmodule Mix.Tasks.ExAwsConfigurator.Setup do
  @shortdoc "Ensure all SNS topics and SQS queues declared in config exist"

  @moduledoc """
  Runs the bootstrapper standalone, without starting the application.

  Useful in a deploy step that provisions infrastructure before the app itself
  starts, or to re-reconcile AWS state after changing the config.

      mix ex_aws_configurator.setup

  The task is idempotent — safe to re-run on every deploy.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    Application.ensure_all_started(:ex_aws)
    Application.ensure_all_started(:hackney)
    ExAwsConfigurator.Bootstrapper.run!()
    :ok
  end
end
