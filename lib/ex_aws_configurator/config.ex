defmodule ExAwsConfigurator.Config do
  @moduledoc """
  Loads and validates the application config into normalized structs.

  Called once at boot by the bootstrapper, and again by `mix
  ex_aws_configurator.setup`. Every validation error aborts boot — the lib
  would rather crash a deploy than silently create diverging AWS resources.

  ## Expected shape

      config :ex_aws_configurator,
        queue_prefix: "billing-dev",
        topics: [%{name: :orders}, %{name: :payments, fifo: true}],
        external_topics: [
          %{name: :shipment_updates, prefix: "shipping"},
          %{name: :partner_feed, arn: "arn:aws:sns:us-east-1:1234:partner-feed"}
        ],
        queues: [
          %{
            name: :orders_events,
            subscribe_to: [:orders, :shipment_updates]
          }
        ]
  """

  alias ExAwsConfigurator.Config.{ExternalTopic, Queue, Topic}

  defstruct queue_prefix: nil, topics: [], external_topics: [], queues: []

  @type t :: %__MODULE__{
          queue_prefix: String.t() | nil,
          topics: [Topic.t()],
          external_topics: [ExternalTopic.t()],
          queues: [Queue.t()]
        }

  @doc """
  Load from the application env and validate. Raises `ArgumentError` on any
  validation failure, with every problem found concatenated in the message.
  """
  @spec load!() :: t()
  def load! do
    raw = Application.get_all_env(:ex_aws_configurator)
    load!(raw)
  end

  @spec load!(keyword() | map()) :: t()
  def load!(raw) do
    detect_legacy!(raw)

    config = %__MODULE__{
      queue_prefix: get(raw, :queue_prefix),
      topics: raw |> get(:topics, []) |> Enum.map(&Topic.from_map/1),
      external_topics: raw |> get(:external_topics, []) |> Enum.map(&ExternalTopic.from_map/1),
      queues: raw |> get(:queues, []) |> Enum.map(&Queue.from_map/1)
    }

    case validate(config) do
      :ok -> config
      {:error, problems} -> raise ArgumentError, format_problems(problems)
    end
  end

  @doc """
  Validate a loaded config. Returns `:ok` or `{:error, [reason, ...]}`.
  """
  @spec validate(t()) :: :ok | {:error, [String.t()]}
  def validate(%__MODULE__{} = config) do
    problems =
      []
      |> check_queue_prefix(config)
      |> check_unique_topic_names(config)
      |> check_unique_queue_names(config)
      |> check_external_topic_shape(config)
      |> check_subscriptions_resolve(config)
      |> check_fifo_naming(config)
      |> Enum.reverse()

    if problems == [], do: :ok, else: {:error, problems}
  end

  defp get(kw, key, default \\ nil) when is_list(kw) do
    Keyword.get(kw, key, default)
  end

  # Detect v1.x config shape and raise a migration-oriented error before
  # validation. The strong signals are: topics/queues declared as maps (v1)
  # rather than lists (v2); top-level identity keys that v2 resolves via STS;
  # and the v1-only nested `attributes`/`options`/`topics` keys on a queue.
  @legacy_top_level_keys ~w[account_id environment]a
  @legacy_queue_keys ~w[attributes options topics prefix environment]a

  defp detect_legacy!(raw) when is_list(raw) do
    signals =
      []
      |> collect_legacy_shape(raw, :topics)
      |> collect_legacy_shape(raw, :queues)
      |> collect_legacy_top_level(raw)
      |> collect_legacy_queue_keys(raw)

    case signals do
      [] -> :ok
      _ -> raise ArgumentError, legacy_message(signals)
    end
  end

  defp detect_legacy!(_), do: :ok

  defp collect_legacy_shape(signals, raw, key) do
    case Keyword.get(raw, key) do
      %{} = _map -> ["`#{key}` is a map — v2 expects a list of maps" | signals]
      _ -> signals
    end
  end

  defp collect_legacy_top_level(signals, raw) do
    Enum.reduce(@legacy_top_level_keys, signals, fn key, acc ->
      if Keyword.has_key?(raw, key) do
        ["top-level `:#{key}` is no longer used (v2 resolves it via STS)" | acc]
      else
        acc
      end
    end)
  end

  defp collect_legacy_queue_keys(signals, raw) do
    case Keyword.get(raw, :queues) do
      queues when is_list(queues) ->
        queues
        |> Enum.flat_map(&legacy_keys_in_queue/1)
        |> Enum.uniq()
        |> case do
          [] ->
            signals

          keys ->
            ["queue entries use removed key(s): #{inspect(keys)}" | signals]
        end

      _ ->
        signals
    end
  end

  defp legacy_keys_in_queue(%{} = queue) do
    queue
    |> Map.keys()
    |> Enum.filter(&(&1 in @legacy_queue_keys))
  end

  defp legacy_keys_in_queue(_), do: []

  defp legacy_message(signals) do
    """
    ex_aws_configurator v2 detected v1.x-style configuration:

      - #{Enum.join(Enum.reverse(signals), "\n      - ")}

    v2 shape (see README for full reference):

        config :ex_aws_configurator,
          queue_prefix: "billing-\#{config_env()}",
          topics: [%{name: :orders}, %{name: :payments, fifo: true}],
          external_topics: [
            %{name: :shipment_updates, prefix: "shipping"},
            %{name: :partner_feed, arn: "arn:aws:sns:us-east-1:1234:partner-feed"}
          ],
          queues: [
            %{
              name: :orders_events,
              subscribe_to: [:orders, :shipment_updates],
              visibility_timeout: 60,
              dlq: true
            }
          ]

    Key migration points:
      * topics/queues are lists of maps (not maps keyed by atom)
      * each entry has an explicit :name
      * queue :topics becomes :subscribe_to
      * per-queue :attributes/:options flatten into top-level keys
      * :account_id/:region are resolved from AWS STS; remove from config
      * DLQ: use :dlq (true | false | %{max_receive_count: _, ...}) — removes :options
    """
  end

  defp check_queue_prefix(problems, %__MODULE__{queue_prefix: nil}),
    do: ["queue_prefix is required" | problems]

  defp check_queue_prefix(problems, %__MODULE__{queue_prefix: p}) when is_binary(p) and p != "",
    do: problems

  defp check_queue_prefix(problems, _),
    do: ["queue_prefix must be a non-empty string" | problems]

  defp check_unique_topic_names(problems, %{topics: topics, external_topics: externals}) do
    all = Enum.map(topics, & &1.name) ++ Enum.map(externals, & &1.name)

    case all -- Enum.uniq(all) do
      [] -> problems
      dupes -> ["topic name(s) duplicated (local vs external): #{inspect(dupes)}" | problems]
    end
  end

  defp check_unique_queue_names(problems, %{queues: queues}) do
    names = Enum.map(queues, & &1.name)

    case names -- Enum.uniq(names) do
      [] -> problems
      dupes -> ["queue name(s) duplicated: #{inspect(dupes)}" | problems]
    end
  end

  defp check_external_topic_shape(problems, %{external_topics: externals}) do
    Enum.reduce(externals, problems, fn ext, acc ->
      cond do
        is_nil(ext.name) ->
          ["external_topic missing :name" | acc]

        is_binary(ext.arn) ->
          acc

        is_binary(ext.prefix) ->
          acc

        true ->
          ["external_topic #{inspect(ext.name)} needs :arn or :prefix" | acc]
      end
    end)
  end

  defp check_subscriptions_resolve(problems, %{
         queues: queues,
         topics: topics,
         external_topics: externals
       }) do
    known = MapSet.new(Enum.map(topics, & &1.name) ++ Enum.map(externals, & &1.name))

    Enum.reduce(queues, problems, fn queue, acc ->
      queue.subscribe_to
      |> Enum.reject(&MapSet.member?(known, &1))
      |> case do
        [] ->
          acc

        missing ->
          ["queue #{inspect(queue.name)} subscribes to unknown topic(s): #{inspect(missing)}" | acc]
      end
    end)
  end

  defp check_fifo_naming(problems, %{queues: queues, topics: topics}) do
    # A FIFO queue can only subscribe to FIFO topics (AWS constraint).
    topic_fifo = Map.new(topics, &{&1.name, &1.fifo})

    Enum.reduce(queues, problems, fn queue, acc ->
      if queue.fifo do
        non_fifo =
          queue.subscribe_to
          |> Enum.filter(&(Map.get(topic_fifo, &1) == false))

        case non_fifo do
          [] -> acc
          bad -> ["FIFO queue #{inspect(queue.name)} subscribes to non-FIFO topic(s): #{inspect(bad)}" | acc]
        end
      else
        acc
      end
    end)
  end

  defp format_problems(problems) do
    "invalid ex_aws_configurator config:\n  - " <> Enum.join(problems, "\n  - ")
  end
end
