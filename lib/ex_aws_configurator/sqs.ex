defmodule ExAwsConfigurator.SQS do
  @moduledoc """
  SQS adapter: creates and updates queues (and their dead letter queues), subscribes
  them to topics and sends messages.

  Every function accepts either a `ExAwsConfigurator.Queue`/`ExAwsConfigurator.Topic`
  struct or the atom that names the resource in the configuration. The atom form
  fetches the struct with `ExAwsConfigurator.get_queue/1`/`get_topic/1` and delegates
  to the struct form.
  """

  require Logger

  alias ExAws.{SNS, SQS}
  alias ExAwsConfigurator.{Queue, Topic}

  @raw_message_delivery "raw_message_delivery"
  @fifo_attributes [:content_based_deduplication, :fifo_queue]
  # Attributes that AWS does not allow changing after the queue exists.
  @immutable_attributes [:fifo_queue]
  @non_existent_queue_codes ["AWS.SimpleQueueService.NonExistentQueue", "QueueDoesNotExist"]
  @authorization_error "AuthorizationError"

  @doc """
  Create an sqs queue, or update its mutable attributes (policy, redrive policy,
  timeouts...) when it already exists. That method do NOT subscribe on any topic.

  When the queue has a dead letter queue (`options.dead_letter_queue`), the dead letter
  queue (`ExAwsConfigurator.Queue.dead_letter_queue/1`) is ensured first; if that fails
  the error is returned and the queue itself is not touched, so a queue never points its
  redrive policy to a dead letter queue that does not exist.

  raises `ExAwsConfigurator.NoResultsError` if the atom form is used and no
  configuration was found.

  for the example below, we will consider the following settings

      # config/config.exs

      config :ex_aws_configurator,
        ...
        queues: %{
          an_queue: %{
            environment: "environment",
            region: "us-east-1",
            prefix: "queue_prefix",
            topics: [:an_topic]
          }
        },
        topics: %{
          an_topic: %{
            region: "us-east-1",
            prefix: "topic_prefix",
            environment: "environment"
          }
        }

  ## Examples

      ExAwsConfigurator.SQS.create_queue(:an_queue)
      #=> {:ok, term()}

  will create an queue named `prefix + environment + map_key`, the result will be _queue_prefix_environment_an_queue_ on region _us-east-1_

  the response term() will be the `ExAws` response without any modification

      ExAwsConfigurator.SQS.create_queue(:not_exist)
      #=> ** (ExAwsConfigurator.NoResultsError) the configuration for queue not_exist is not set

  """
  @spec create_queue(Queue.t() | atom, map) :: {:ok, term} | {:error, term}
  def create_queue(queue, tags \\ %{})

  def create_queue(%Queue{options: %{dead_letter_queue: true}} = queue, tags) do
    with {:ok, _} <- queue |> Queue.dead_letter_queue() |> create_queue(tags) do
      ensure_queue(queue, tags)
    end
  end

  def create_queue(%Queue{} = queue, tags), do: ensure_queue(queue, tags)

  def create_queue(queue_name, tags) when is_atom(queue_name),
    do: queue_name |> ExAwsConfigurator.get_queue() |> create_queue(tags)

  defp ensure_queue(queue, tags) do
    full_name = Queue.full_name(queue)

    Logger.info(~s"""
    \n\n  Ensuring queue #{full_name} on #{queue.region}
        Attributes:
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} content_based_deduplication: #{queue.attributes.content_based_deduplication}
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} delay_seconds: #{queue.attributes.delay_seconds}
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} fifo_queue: #{queue.attributes.fifo_queue}
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} maximum_message_size: #{queue.attributes.maximum_message_size}
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} message_retention_period: #{queue.attributes.message_retention_period}
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} receive_message_wait_time_seconds: #{queue.attributes.receive_message_wait_time_seconds}
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} visibility_timeout: #{queue.attributes.visibility_timeout}
        Options:
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} dead_letter_queue: #{queue.options.dead_letter_queue}
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} dead_letter_queue_suffix: #{queue.options.dead_letter_queue_suffix}
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} max_receive_count: #{queue.options.max_receive_count}
    """)

    create_or_update_queue(full_name, queue, tags)
  end

  @doc """
  Subscribe a queue into a topic.

  When the topic belongs to an external account, the subscribe call only succeeds if the
  topic owner allows `sns:Subscribe` from this account. When it is denied:

    * with `on_unauthorized: :error` (default) the `{:error, term}` is returned as is;
    * with `on_unauthorized: :warn` a warning with the policy statement the owner must
      add is logged and `{:ok, :unauthorized}` is returned.
  """
  @spec subscribe(Queue.t() | atom, Topic.t() | atom) :: {:ok, term} | {:error, term}
  def subscribe(%Queue{} = queue, %Topic{} = topic) do
    Logger.info("Subscribe queue #{Queue.full_name(queue)} to topic #{Topic.full_name(topic)}")

    result =
      topic
      |> Topic.arn()
      |> SNS.subscribe("sqs", Queue.arn(queue))
      |> ExAws.request(region: topic.region)

    case result do
      {:ok, %{body: %{subscription_arn: subscription_arn}}} ->
        if queue.options.raw_message_delivery,
          do: set_raw_message_delivery(subscription_arn, topic.region),
          else: result

      {:error, {:http_error, _, %{code: @authorization_error}} = reason} ->
        handle_unauthorized(topic, queue, reason)

      {:error, _} = error ->
        error
    end
  end

  def subscribe(queue, topic), do: subscribe(fetch_queue(queue), fetch_topic(topic))

  @doc """
  Send message to a queue build the correct queue name based on queue configuration

  raises `ExAwsConfigurator.NoResultsError` if the atom form is used and no
  configuration was found.

  for the example below, we will consider the following settings

      # config/config.exs

      config :ex_aws_configurator,
        ...
        queues: %{
          an_queue: %{
            environment: "environment",
            region: "us-east-1",
            prefix: "queue_prefix",
            topics: [:an_topic]
          }
        }

  ## Examples

      ExAwsConfigurator.SQS.send_message(:an_queue, "message")
      #=> {:ok, term()}

  will send a message to queue named _queue_prefix_environment_an_queue_ on region _us-east-1_

  the response term() will be the `ExAws` response without any modification

      ExAwsConfigurator.SQS.send_message(:not_exist, "message")
      #=> ** (ExAwsConfigurator.NoResultsError) the configuration for queue not_exist is not set

  another possible error is when configuration exists but queue is not created, in this case the response will be {:error, %{status_code: 404, ...}} returned by AWS response

      ExAwsConfigurator.SQS.send_message(:not_created, "message")
      #=> {:error, term()}
  """
  @spec send_message(Queue.t() | atom, String.t(), SQS.sqs_message_opts()) ::
          {:ok, term} | {:error, term}
  def send_message(queue, message, opts \\ [])

  def send_message(%Queue{} = queue, message, opts) do
    Logger.info("Sending message to #{Queue.full_name(queue)}")

    queue
    |> Queue.url()
    |> SQS.send_message(message, opts)
    |> ExAws.request(region: queue.region)
  end

  def send_message(queue_name, message, opts) when is_atom(queue_name),
    do: queue_name |> ExAwsConfigurator.get_queue() |> send_message(message, opts)

  defp fetch_queue(%Queue{} = queue), do: queue
  defp fetch_queue(name) when is_atom(name), do: ExAwsConfigurator.get_queue(name)

  defp fetch_topic(%Topic{} = topic), do: topic
  defp fetch_topic(name) when is_atom(name), do: ExAwsConfigurator.get_topic(name)

  defp create_or_update_queue(full_name, queue, tags) do
    case full_name |> SQS.get_queue_url() |> ExAws.request(region: queue.region) do
      {:ok, %{body: %{queue_url: queue_url}}} ->
        update_queue_on_sqs(full_name, queue_url, queue, tags)

      {:error, {:http_error, _, %{code: code}}} when code in @non_existent_queue_codes ->
        create_queue_on_sqs(full_name, queue, tags)

      {:error, term} = error ->
        Logger.error(~s"""
        \n\n  #{IO.ANSI.red()}Error fetching queue #{full_name} on #{queue.region}, reason: #{inspect(term)}#{IO.ANSI.reset()}
        """)

        error
    end
  end

  defp create_queue_on_sqs(full_name, queue, tags) do
    attributes =
      queue.attributes
      |> Map.from_struct()
      |> Enum.reject(fn {key, value} -> key in @fifo_attributes and is_nil(value) end)

    result =
      full_name
      |> SQS.create_queue(attributes, tags)
      |> ExAws.request(region: queue.region)

    log_result(result, {"created", "creating"}, full_name, queue)
  end

  defp update_queue_on_sqs(full_name, queue_url, queue, tags) do
    attributes =
      queue.attributes
      |> Map.from_struct()
      |> Enum.reject(fn {key, value} -> key in @immutable_attributes or is_nil(value) end)

    result =
      with {:ok, _} <-
             queue_url
             |> SQS.set_queue_attributes(attributes)
             |> ExAws.request(region: queue.region) do
        tag_queue(queue_url, queue, tags)
      end

    log_result(result, {"updated", "updating"}, full_name, queue)
  end

  defp tag_queue(_queue_url, _queue, tags) when map_size(tags) == 0,
    do: {:ok, %{status_code: 200}}

  defp tag_queue(queue_url, queue, tags) do
    queue_url
    |> SQS.tag_queue(tags)
    |> ExAws.request(region: queue.region)
  end

  defp log_result({:ok, _} = result, {done, _doing}, full_name, queue) do
    Logger.info(~s"""
    \n\n  #{IO.ANSI.green()}Queue #{full_name} #{done} successfully on #{queue.region}#{IO.ANSI.reset()}
    """)

    result
  end

  defp log_result({:error, term} = result, {_done, doing}, full_name, queue) do
    Logger.error(~s"""
    \n\n  #{IO.ANSI.red()}Error #{doing} queue #{full_name} on #{queue.region}, reason: #{inspect(term)}#{IO.ANSI.reset()}
    """)

    result
  end

  defp handle_unauthorized(%Topic{external: true, on_unauthorized: :warn} = topic, queue, reason) do
    Logger.warning(~s"""
    Not authorized to subscribe queue #{Queue.full_name(queue)} to the external topic #{Topic.arn(topic)}, reason: #{inspect(reason)}
    The subscription was skipped because the topic is configured with `on_unauthorized: :warn`.
    Ask the topic owner (account #{topic.account.id}) to add this statement to the topic policy:
    #{subscribe_statement(topic, queue)}
    """)

    {:ok, :unauthorized}
  end

  defp handle_unauthorized(topic, queue, reason) do
    Logger.error(
      "Not authorized to subscribe queue #{Queue.full_name(queue)} to topic #{Topic.arn(topic)}, " <>
        "reason: #{inspect(reason)}"
    )

    {:error, reason}
  end

  defp subscribe_statement(topic, queue) do
    Jason.encode!(
      %{
        Sid: "AllowSubscribeFrom#{queue.account.id}",
        Effect: "Allow",
        Principal: %{AWS: "arn:aws:iam::#{queue.account.id}:root"},
        Action: ["sns:Subscribe", "sns:GetTopicAttributes"],
        Resource: Topic.arn(topic)
      },
      pretty: true
    )
  end

  defp set_raw_message_delivery(subscription_arn, region) do
    @raw_message_delivery
    |> SNS.set_subscription_attributes(true, subscription_arn)
    |> ExAws.request(region: region)
  end
end
