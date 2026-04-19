defmodule ExAwsConfigurator.Ensure.Topic do
  @moduledoc false

  alias ExAwsConfigurator.Aws.Sns
  alias ExAwsConfigurator.Resolved

  @spec run(Resolved.Topic.t()) :: :ok
  def run(%Resolved.Topic{config: config, full_name: full_name}) do
    attrs = build_attrs(config)

    case Sns.create_topic(full_name, attrs) do
      {:ok, _arn} -> :ok
      {:error, reason} -> raise "failed to create topic #{full_name}: #{inspect(reason)}"
    end
  end

  defp build_attrs(%{fifo: true, content_based_deduplication: dedup}) do
    [fifo_topic: true, content_based_deduplication: dedup]
  end

  defp build_attrs(_), do: []
end
