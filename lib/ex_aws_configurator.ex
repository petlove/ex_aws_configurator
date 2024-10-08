defmodule ExAwsConfigurator do
  @moduledoc """
  Documentation for `ExAwsConfigurator`.
  """

  require Logger

  alias ExAwsConfigurator.{
    Queue,
    QueueAttributes,
    QueueOptions,
    SNS,
    SQS,
    Topic,
    TopicAttributes
  }

  @doc """
  Create all topics, create all queue and all subscrition present into configuration

  We recommended that use this only if you change some configuration, however you can add this
  method to trigger by CI ever deploy
  """
  def setup do
    topics = get_env(:topics)
    queues = get_env(:queues)

    topics_not_created =
      Enum.reduce(topics, [], fn {key, _}, acc ->
        case SNS.create_topic(key) do
          {:ok, _} ->
            acc

          {:error, _} ->
            [key | acc]
        end
      end)

    queues_not_created =
      Enum.reduce(queues, [], fn {queue_name, queue_config}, acc ->
        case SQS.create_queue(queue_name) do
          {:ok, _} ->
            Enum.each(queue_config[:topics], &SQS.subscribe(queue_name, &1))
            acc

          {:error, _} ->
            [queue_name | acc]
        end
      end)

    cond do
      length(topics_not_created) > 0 ->
        Logger.error("Some topics was not created: #{inspect(topics_not_created)}")
        {:error, :topics}

      length(queues_not_created) > 0 ->
        Logger.error("Some queues was not created: #{inspect(queues_not_created)}")
        {:error, :queues}

      true ->
        :ok
    end
  end

  @doc """
  Create all topics, create all queue and all subscrition present into configuration,
  can raise an exception in case of error.

  We recommended that use this only if you change some configuration, however you can add this
  method to trigger by CI ever deploy
  """
  @spec setup!() :: :ok | no_return
  def setup! do
    case setup() do
      {:error, type} ->
        raise ExAwsConfigurator.SetupError, type: type

      :ok ->
        :ok
    end
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
        queue =
          %Queue{name: queue_name}
          |> struct(%{
            environment: Application.get_env(:ex_aws_configurator, :environment),
            region: Application.get_env(:ex_aws_configurator, :region)
          })
          |> struct(value)
          |> struct(%{topics: Enum.map(Map.get(value, :topics, []), &get_topic/1)})

        queue
        |> struct(%{options: struct(%QueueOptions{}, Map.get(value, :options, []))})
        |> struct(%{
          attributes:
            struct(%QueueAttributes{policy: Queue.policy(queue)}, Map.get(value, :attributes, []))
        })

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
      {:ok, value} ->
        %Topic{name: topic_name}
        |> struct(%{
          environment: Application.get_env(:ex_aws_configurator, :environment),
          region: Application.get_env(:ex_aws_configurator, :region)
        })
        |> struct(value)
        |> struct(%{attributes: struct(%TopicAttributes{}, Map.get(value, :attributes, []))})

      :error ->
        raise ExAwsConfigurator.NoResultsError, type: :topic, name: topic_name
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
