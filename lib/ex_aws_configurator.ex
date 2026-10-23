defmodule ExAwsConfigurator do
  @moduledoc """
  Documentation for `ExAwsConfigurator`.
  """

  require Logger

  alias ExAwsConfigurator.{Account, Config, Queue, SNS, SQS, Telemetry, Topic}

  @doc """
  Ensure every topic, queue and subscription present in the configuration exists on AWS.

  The whole configuration is resolved and validated first (see
  `ExAwsConfigurator.Config.load/0`), then the setup runs in three phases and is
  idempotent:

    1. topics: created when missing, updated otherwise. Topics owned by an external
       account are skipped (their owner manages them);
    2. queues (and their dead letter queues): created when missing, updated otherwise;
    3. subscriptions: every queue is subscribed to its topics. For external topics the
       subscribe call is refused when the topic owner did not allow it; the setup fails
       unless the topic is configured with `on_unauthorized: :warn`.

  It is safe to run on every deploy. Returns `{:error, :topics | :queues | :subscriptions}`
  naming the first phase that failed.

  Emits the `[:ex_aws_configurator, :setup]` span, and every resource emits its own
  (see `ExAwsConfigurator.Telemetry`).
  """
  @spec setup() :: :ok | {:error, :topics | :queues | :subscriptions}
  def setup do
    Telemetry.span(:setup, %{}, fn -> Config.load() |> run_setup() end)
  end

  defp run_setup(%Config{topics: topics, queues: queues}) do
    topics_not_created =
      for {name, topic} <- topics, match?({:error, _}, SNS.create_topic(topic)), do: name

    queues_not_created =
      for {name, queue} <- queues, match?({:error, _}, SQS.create_queue(queue)), do: name

    subscriptions_not_created =
      for {name, queue} <- queues,
          name not in queues_not_created,
          topic <- queue.topics,
          match?({:error, _}, SQS.subscribe(queue, topic)),
          do: {name, topic.name}

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
end
