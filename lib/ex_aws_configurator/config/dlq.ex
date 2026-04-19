defmodule ExAwsConfigurator.Config.Dlq do
  @moduledoc """
  Dead-letter queue configuration for a parent queue.

  The DLQ is a plain SQS queue named `<parent>_failures` (with the same prefix as
  its parent) that the parent redrives to after `max_receive_count` failed
  receives. `message_retention` defaults to AWS's maximum (14 days) because
  failed messages are worth keeping around.
  """

  # 14 days, AWS SQS maximum
  @max_retention_seconds 1_209_600

  defstruct max_receive_count: 5,
            message_retention: @max_retention_seconds,
            suffix: "_failures"

  @type t :: %__MODULE__{
          max_receive_count: pos_integer(),
          message_retention: pos_integer(),
          suffix: String.t()
        }

  @doc """
  Build a Dlq struct from the declared `:dlq` option on a queue.

  Accepts `true` (defaults), `false`/`nil` (disabled → returns `nil`), or a map
  of overrides merged on top of the defaults.
  """
  @spec from(true | false | nil | map()) :: t() | nil
  def from(true), do: %__MODULE__{}
  def from(false), do: nil
  def from(nil), do: nil
  def from(%{} = overrides), do: struct!(__MODULE__, overrides)
end
