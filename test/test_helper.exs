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
end
