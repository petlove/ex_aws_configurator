defmodule ExAwsConfigurator do
  @moduledoc """
  Documentation for `ExAwsConfigurator`.
  """

  require Logger

  alias ExAwsConfigurator.{Queue, SNS, SQS, Topic}

  @doc """
  Create all topics, create all queue and all subscrition present into configuration

  We recommended that use this only if you change some configuration, however you can add this
  method to trigger by CI ever deploy
  """
  def setup do
    topics = get_env(:topics)
    queues = get_env(:queues)

    Enum.each(topics, fn {key, _} ->
      SNS.create_topic(key)
    end)

    Enum.each(queues, fn {queue_name, queue_config} ->
      SQS.create_queue(queue_name)

      Enum.each(queue_config[:topics], &SQS.subscribe(queue_name, &1))
    end)
  end

  @doc """
  Fetch queue configurations specific to the :ex_aws_configurator application.

  raises `ExAwsConfigurator.NoResultsError` if no configuration was found.

  ## Example

      ExAwsConfigurator.get_queue(:queue_name)
      #=> %Queue{region: us-east-1, ...}

      ExAwsConfigurator.get_queue(:not_exist)
      #=> ** (ExAwsConfigurator.NoResultsError) the configuration for queue not_exist is not set
  """
  @spec get_queue(atom) :: Queue.t()
  def get_queue(queue_name) when is_atom(queue_name) do
    case Map.fetch(get_env(:queues), queue_name) do
      {:ok, value} ->
        queue = struct(%Queue{name: queue_name}, value)
        queue = struct(queue, %{topics: Enum.map(queue.topics, &get_topic/1)})

        attributes = Keyword.put_new(queue.attributes, :policy, Queue.policy(queue))

        queue
        |> struct(%{options: Keyword.merge(%Queue{}.options, queue.options)})
        |> struct(%{attributes: Keyword.merge(%Queue{}.attributes, attributes)})

      :error ->
        raise ExAwsConfigurator.NoResultsError, type: :queue, name: queue_name
    end
  end

  @doc """
  Fetch topic configurations specific to the :ex_aws_configurator application.

  raises `ExAwsConfigurator.NoResultsError` if no configuration was found.

  ## Example

      ExAwsConfigurator.get_topic(queue_name)
      #=> %Topic{region: us-east-1, ...}

      ExAwsConfigurator.get_topic(:not_exist)
      #=> ** (ExAwsConfigurator.NoResultsError) the configuration for topic not_exist is not set
  """
  @spec get_topic(atom) :: any | no_return
  def get_topic(topic_name) when is_atom(topic_name) do
    case Map.fetch(get_env(:topics), topic_name) do
      {:ok, value} -> struct(%Topic{name: topic_name}, value)
      :error -> raise ExAwsConfigurator.NoResultsError, type: :topic, name: topic_name
    end
  end

  @doc false
  @spec get_env(atom) :: any | no_return
  def get_env(key) when is_atom(key) do
    case Application.fetch_env(:ex_aws_configurator, key) do
      {:ok, {:system, var}} when is_binary(var) ->
        System.get_env(var)

      {:ok, value} ->
        value

      :error ->
        raise ExAwsConfigurator.NoResultsError, name: key
    end
  end
end
