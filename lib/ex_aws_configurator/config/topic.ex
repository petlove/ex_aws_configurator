defmodule ExAwsConfigurator.Config.Topic do
  @moduledoc """
  A topic declared by this application.

  The app owns it: the bootstrapper will create it (idempotently) and any queues
  declared locally may subscribe to it.
  """

  @enforce_keys [:name]
  defstruct [:name, fifo: false, content_based_deduplication: false]

  @type t :: %__MODULE__{
          name: atom(),
          fifo: boolean(),
          content_based_deduplication: boolean()
        }

  @spec from_map(map()) :: t()
  def from_map(%{name: name} = attrs) when is_atom(name) do
    struct!(__MODULE__, Map.take(attrs, [:name, :fifo, :content_based_deduplication]))
  end
end
