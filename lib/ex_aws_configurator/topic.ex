defmodule ExAwsConfigurator.Topic do
  require Logger

  @type t :: %__MODULE__{
          name: binary(),
          region: binary(),
          environment: binary(),
          prefix: binary()
        }

  defstruct name: nil,
            environment: Mix.env(),
            region: ExAws.Config.new(:sns).region,
            prefix: nil

  @doc false
  def arn(%__MODULE__{} = queue) do
    ["arn:aws:sns", queue.region, ExAwsConfigurator.get_env(:account_id), full_name(queue)]
    |> Enum.join(":")
  end

  @doc false
  def full_name(%__MODULE__{} = topic) do
    [topic.prefix, topic.environment, topic.name]
    |> Enum.filter(&(!is_nil(&1)))
    |> Enum.join("_")
  end
end
