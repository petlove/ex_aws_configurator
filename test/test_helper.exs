ExUnit.start()
{:ok, _} = Application.ensure_all_started(:ex_machina)

defmodule ExAwsConfigurator.Case do
  use ExUnit.CaseTemplate

  using(_) do
    quote do
      import ExAwsConfigurator.Factory

      import unquote(__MODULE__)
    end
  end

  def add_queue_to_config(queue_config) do
    queues = ExAwsConfigurator.get_env(:queues)

    Application.put_env(:ex_aws_configurator, :queues, Map.merge(queues, queue_config))
  end

  def add_topic_to_config(topic_config) do
    topics = ExAwsConfigurator.get_env(:topics)

    Application.put_env(:ex_aws_configurator, :topics, Map.merge(topics, topic_config))
  end

  @doc "Declare the `:external` account (owned by `ExAwsConfigurator.HttpStub.external_account_id/0`)."
  def add_external_account_to_config do
    accounts = Application.get_env(:ex_aws_configurator, :accounts, %{})

    Application.put_env(
      :ex_aws_configurator,
      :accounts,
      Map.put(accounts, :external, %{
        id: ExAwsConfigurator.HttpStub.external_account_id(),
        region: "sa-east-1"
      })
    )
  end
end
