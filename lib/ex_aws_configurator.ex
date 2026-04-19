defmodule ExAwsConfigurator do
  @moduledoc """
  Public API for publishing to SNS topics and sending to SQS queues using the
  logical names declared in application config.

  The Bootstrapper resolves each logical name (`:orders`, `:orders_events`,
  etc.) into a concrete ARN/URL at boot; these functions simply look up the
  resolved value in the Registry and delegate to the AWS wrapper.

  ## Payloads

  Binary payloads pass through untouched. Anything else is JSON-encoded with
  `Jason`. Callers that need a different encoding should encode before calling.

  ## FIFO

  FIFO topics/queues require `:message_group_id` in the `opts` — we raise
  `ArgumentError` at the call site rather than letting AWS reject the request.
  `:message_deduplication_id` is not validated locally (AWS enforces it based
  on `content_based_deduplication`).

  ## Telemetry

  Four spans are emitted, each with `:start`, `:stop` and `:exception` events:

    * `[:ex_aws_configurator, :publish]`
    * `[:ex_aws_configurator, :send_to_queue]`
    * `[:ex_aws_configurator, :publish_batch]`
    * `[:ex_aws_configurator, :send_to_queue_batch]`

  `:start` metadata carries the logical name; `:stop` adds `:message_id` on
  success or `:error` on failure.
  """

  alias ExAwsConfigurator.Aws.{Sns, Sqs}
  alias ExAwsConfigurator.{Bootstrapper, Registry, Resolved}

  @type payload :: term()
  @type batch_entry :: %{required(:payload) => payload(), optional(atom()) => term()}

  @doc """
  Run the provisioning pipeline from code.

  Equivalent to `mix ex_aws_configurator.setup`, but callable from Elixir — use
  this from a release boot script, a migration-like task, or any context where
  you want explicit control instead of (or in addition to) the automatic boot
  bootstrapper.

  Idempotent: re-running it against already-provisioned AWS resources is a
  no-op apart from the `SetQueueAttributes` / `SetQueuePolicy` calls that
  reconcile drift. Raises if anything fails.
  """
  @spec setup!() :: Resolved.t()
  defdelegate setup!(), to: Bootstrapper, as: :run!

  @doc """
  Publish a single message to an SNS topic by logical name.
  """
  @spec publish(atom(), payload(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def publish(topic_name, payload, opts \\ []) when is_atom(topic_name) do
    arn = Registry.topic_arn!(topic_name)
    topic = topic_by_name(topic_name)
    validate_fifo!(topic, opts, topic_name)

    message = encode(payload)

    :telemetry.span(
      [:ex_aws_configurator, :publish],
      %{topic: topic_name},
      fn ->
        case Sns.publish(arn, message, opts) do
          {:ok, id} = ok -> {ok, %{topic: topic_name, message_id: id}}
          {:error, reason} = err -> {err, %{topic: topic_name, error: reason}}
        end
      end
    )
  end

  @doc """
  Send a single message to an SQS queue by logical name.
  """
  @spec send_to_queue(atom(), payload(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_to_queue(queue_name, payload, opts \\ []) when is_atom(queue_name) do
    queue = Registry.queue!(queue_name)
    validate_fifo!(queue, opts, queue_name)

    message = encode(payload)

    :telemetry.span(
      [:ex_aws_configurator, :send_to_queue],
      %{queue: queue_name},
      fn ->
        case Sqs.send_message(queue.url, message, opts) do
          {:ok, id} = ok -> {ok, %{queue: queue_name, message_id: id}}
          {:error, reason} = err -> {err, %{queue: queue_name, error: reason}}
        end
      end
    )
  end

  @doc """
  Publish a batch of messages to an SNS topic.

  Each entry is a map with at minimum `:payload`; optional keys include `:id`
  (auto-generated if absent), `:message_group_id`, `:message_deduplication_id`,
  `:message_attributes`, `:subject`.

  Returns `{:ok, %{successful: [...], failed: [...]}}` — AWS reports partial
  success at the entry level, so the caller must inspect both lists.
  """
  @spec publish_batch(atom(), [batch_entry()]) ::
          {:ok, map()} | {:error, term()}
  def publish_batch(topic_name, entries) when is_atom(topic_name) and is_list(entries) do
    arn = Registry.topic_arn!(topic_name)
    aws_entries = normalize_batch(entries, :message)

    :telemetry.span(
      [:ex_aws_configurator, :publish_batch],
      %{topic: topic_name, count: length(entries)},
      fn ->
        case Sns.publish_batch(arn, aws_entries) do
          {:ok, _} = ok -> {ok, %{topic: topic_name, count: length(entries)}}
          {:error, reason} = err -> {err, %{topic: topic_name, error: reason}}
        end
      end
    )
  end

  @doc """
  Send a batch of messages to an SQS queue. Entry shape matches `publish_batch/2`
  except that the AWS field is `message_body` — callers still pass `:payload`.
  """
  @spec send_to_queue_batch(atom(), [batch_entry()]) ::
          {:ok, map()} | {:error, term()}
  def send_to_queue_batch(queue_name, entries) when is_atom(queue_name) and is_list(entries) do
    queue = Registry.queue!(queue_name)
    aws_entries = normalize_batch(entries, :message_body)

    :telemetry.span(
      [:ex_aws_configurator, :send_to_queue_batch],
      %{queue: queue_name, count: length(entries)},
      fn ->
        case Sqs.send_message_batch(queue.url, aws_entries) do
          {:ok, _} = ok -> {ok, %{queue: queue_name, count: length(entries)}}
          {:error, reason} = err -> {err, %{queue: queue_name, error: reason}}
        end
      end
    )
  end

  # --- helpers -------------------------------------------------------------

  defp encode(payload) when is_binary(payload), do: payload
  defp encode(payload), do: Jason.encode!(payload)

  defp normalize_batch(entries, payload_key) do
    entries
    |> Enum.with_index()
    |> Enum.map(fn {entry, i} ->
      payload =
        case Map.fetch(entry, :payload) do
          {:ok, p} -> p
          :error -> raise ArgumentError, "batch entry missing :payload key"
        end

      entry
      |> Map.delete(:payload)
      |> Map.put(payload_key, encode(payload))
      |> Map.put_new(:id, "msg_#{i}")
    end)
  end

  defp topic_by_name(name) do
    resolved = Registry.resolved!()
    Map.get(resolved.topics, name) || Map.get(resolved.external_topics, name) ||
      raise ArgumentError, "unknown topic #{inspect(name)}"
  end

  defp validate_fifo!(%Resolved.Topic{config: %{fifo: true}}, opts, name),
    do: require_group_id!(opts, name)

  defp validate_fifo!(%Resolved.ExternalTopic{config: %{fifo: true}}, opts, name),
    do: require_group_id!(opts, name)

  defp validate_fifo!(%Resolved.Queue{config: %{fifo: true}}, opts, name),
    do: require_group_id!(opts, name)

  defp validate_fifo!(_, _, _), do: :ok

  defp require_group_id!(opts, name) do
    unless Keyword.has_key?(opts, :message_group_id) do
      raise ArgumentError,
            "FIFO #{inspect(name)} requires :message_group_id in opts"
    end
  end
end
