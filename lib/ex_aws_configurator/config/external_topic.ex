defmodule ExAwsConfigurator.Config.ExternalTopic do
  @moduledoc """
  A topic owned by another service/account.

  The app does not create it — the resolver only builds its ARN so local queues
  can subscribe. Two shapes are supported:

    * `:arn` — full ARN provided, nothing is inferred.
    * `:prefix` + `:name` — ARN is composed as
      `arn:aws:sns:<region>:<account_id>:<prefix>-<name>`, with region and
      account_id falling back to the current AWS identity if omitted.
  """

  defstruct [:name, :prefix, :account_id, :region, :arn, fifo: false]

  @type t :: %__MODULE__{
          name: atom(),
          prefix: String.t() | nil,
          account_id: String.t() | nil,
          region: String.t() | nil,
          arn: String.t() | nil,
          fifo: boolean()
        }

  @spec from_map(map()) :: t()
  def from_map(attrs) do
    struct!(
      __MODULE__,
      Map.take(attrs, [:name, :prefix, :account_id, :region, :arn, :fifo])
    )
  end
end
