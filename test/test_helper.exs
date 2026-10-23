ExUnit.start()
{:ok, _} = Application.ensure_all_started(:ex_machina)

# The local backend keeps the resources between runs, so the factories mark every
# name with a run id to tell "created" from "updated" in the assertions.
:persistent_term.put(
  {ExAwsConfigurator.Factory, :run_id},
  Integer.to_string(System.os_time(:millisecond), 36)
)

defmodule ExAwsConfigurator.Case do
  use ExUnit.CaseTemplate

  using(_) do
    quote do
      import ExAwsConfigurator.Factory

      import unquote(__MODULE__)
    end
  end

  @app :ex_aws_configurator

  def add_queue_to_config(queue_config) do
    queues = Application.get_env(@app, :queues, %{})

    Application.put_env(@app, :queues, Map.merge(queues, queue_config))
  end

  def add_topic_to_config(topic_config) do
    topics = Application.get_env(@app, :topics, %{})

    Application.put_env(@app, :topics, Map.merge(topics, topic_config))
  end

  @doc "Declare the `:external` account (owned by `ExAwsConfigurator.HttpStub.external_account_id/0`)."
  def add_external_account_to_config do
    accounts = Application.get_env(@app, :accounts, %{})

    Application.put_env(
      @app,
      :accounts,
      Map.put(accounts, :external, %{
        id: ExAwsConfigurator.HttpStub.external_account_id(),
        region: "sa-east-1"
      })
    )
  end
end
