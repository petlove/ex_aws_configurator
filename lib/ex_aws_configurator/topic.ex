defmodule ExAwsConfigurator.Topic do
  require Logger

  @type t :: %__MODULE__{
          name: binary(),
          region: binary(),
          environment: binary(),
          prefix: binary()
        }

  defstruct [:name, :environment, :region, :prefix]

  @doc "get topic arn"
  @spec arn(t()) :: String.t()
  def arn(%__MODULE__{} = topic) do
    ["arn:aws:sns", topic.region, ExAwsConfigurator.get_env(:account_id), full_name(topic)]
    |> Enum.join(":")
  end

  @doc "get topic full name, its a composition of `prefix + environment + topic.name`"
  @spec full_name(t()) :: String.t()
  def full_name(%__MODULE__{} = topic) do
    [topic.prefix, topic.environment, topic.name]
    |> Enum.filter(&(!is_nil(&1)))
    |> Enum.join("_")
  end
end
