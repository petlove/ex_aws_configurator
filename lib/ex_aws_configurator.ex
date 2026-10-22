defmodule ExAwsConfigurator do
  @moduledoc """
  Documentation for `ExAwsConfigurator`.
  """

  require Logger

  alias ExAwsConfigurator.{Account, Config, Queue, SNS, SQS, Topic}

  @doc """
  Ensure every topic, queue and subscription present in the configuration exists on AWS.

  The setup runs in three phases and is idempotent:

    1. topics: created when missing, updated otherwise. Topics owned by an external
       account are skipped (their owner manages them);
    2. queues (and their dead letter queues): created when missing, updated otherwise;
    3. subscriptions: every queue is subscribed to its topics. For external topics the
       subscribe call is refused when the topic owner did not allow it; the setup fails
       unless the topic is configured with `on_unauthorized: :warn`.

  It is safe to run on every deploy. Returns `{:error, :topics | :queues | :subscriptions}`
  naming the first phase that failed.
  """
  @spec setup() :: :ok | {:error, :topics | :queues | :subscriptions}
  def setup do
    topics = get_env(:topics)
    queues = get_env(:queues)

    topics_not_created =
      for {topic_name, _} <- topics,
          match?({:error, _}, SNS.create_topic(topic_name)),
          do: topic_name

    queues_not_created =
      for {queue_name, _} <- queues,
          match?({:error, _}, SQS.create_queue(queue_name)),
          do: queue_name

    subscriptions_not_created =
      for {queue_name, queue_config} <- queues,
          queue_name not in queues_not_created,
          topic_name <- queue_config[:topics] || [],
          match?({:error, _}, SQS.subscribe(queue_name, topic_name)),
          do: {queue_name, topic_name}

    cond do
      topics_not_created != [] ->
        Logger.error("Some topics was not created: #{inspect(topics_not_created)}")
        {:error, :topics}

      queues_not_created != [] ->
        Logger.error("Some queues was not created: #{inspect(queues_not_created)}")
        {:error, :queues}

      subscriptions_not_created != [] ->
        Logger.error(
          "Some subscriptions was not created (queue, topic): #{inspect(subscriptions_not_created)}"
        )

        {:error, :subscriptions}

      true ->
        :ok
    end
  end

  @doc """
  Same as `setup/0`, but raises `ExAwsConfigurator.SetupError` in case of error.
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
  defdelegate get_queue(queue_name), to: Config

  @doc """
  Fetch topic configurations specific to the :ex_aws_configurator application.

  raises `ExAwsConfigurator.NoResultsError` if no configuration was found.

  ## Example

      ExAwsConfigurator.get_topic(queue_name)
      #=> %Topic{region: us-east-1, ...}

      ExAwsConfigurator.get_topic(:not_exist)
      #=> ** (ExAwsConfigurator.NoResultsError) the configuration for topic not_exist is not set
  """
  @spec get_topic(atom) :: Topic.t()
  defdelegate get_topic(topic_name), to: Config

  @doc """
  Fetch an account by name: `:default` for the one built from `account_id`/`region`, or
  any name declared under the `accounts` key.

  raises `ExAwsConfigurator.NoResultsError` if no configuration was found.
  """
  @spec get_account(atom) :: Account.t()
  defdelegate get_account(name), to: Config

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
