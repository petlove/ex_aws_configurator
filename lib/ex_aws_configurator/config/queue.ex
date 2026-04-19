defmodule ExAwsConfigurator.Config.Queue do
  @moduledoc """
  A queue declared by this application.

  Attribute defaults match AWS SQS defaults where they are sensible and match
  the v1 lib where the v1 default was intentional (e.g. `visibility_timeout:
  60`).

  `:subscribe_to` is a list of topic names (local or external) — the resolver
  validates that every name resolves.

  `:policy` is an optional escape hatch: a 1-arity function
  `(%{queue_arn, topic_arns} -> map)` that returns the full policy document. If
  present, the generated SNS → SQS statement is replaced entirely.
  """

  alias ExAwsConfigurator.Config.Dlq

  @enforce_keys [:name]
  defstruct [
    :name,
    :policy,
    fifo: false,
    content_based_deduplication: false,
    delay_seconds: 0,
    maximum_message_size: 262_144,
    message_retention: 1_209_600,
    receive_message_wait_time: 0,
    visibility_timeout: 60,
    raw_message_delivery: false,
    subscribe_to: [],
    dlq: %Dlq{}
  ]

  @type t :: %__MODULE__{
          name: atom(),
          policy: (map() -> map()) | nil,
          fifo: boolean(),
          content_based_deduplication: boolean(),
          delay_seconds: non_neg_integer(),
          maximum_message_size: pos_integer(),
          message_retention: pos_integer(),
          receive_message_wait_time: non_neg_integer(),
          visibility_timeout: non_neg_integer(),
          raw_message_delivery: boolean(),
          subscribe_to: [atom()],
          dlq: Dlq.t() | nil
        }

  @spec from_map(map()) :: t()
  def from_map(%{name: name} = attrs) when is_atom(name) do
    fields =
      attrs
      |> Map.take([
        :name,
        :policy,
        :fifo,
        :content_based_deduplication,
        :delay_seconds,
        :maximum_message_size,
        :message_retention,
        :receive_message_wait_time,
        :visibility_timeout,
        :raw_message_delivery,
        :subscribe_to
      ])
      |> Map.put(:dlq, Dlq.from(Map.get(attrs, :dlq, true)))

    struct!(__MODULE__, fields)
  end
end
