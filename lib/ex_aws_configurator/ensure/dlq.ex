defmodule ExAwsConfigurator.Ensure.Dlq do
  @moduledoc false

  alias ExAwsConfigurator.Aws.Sqs
  alias ExAwsConfigurator.Resolved

  @existing_codes ~w[QueueAlreadyExists QueueNameExists AWS.SimpleQueueService.QueueNameExists]

  @spec run(Resolved.Dlq.t(), parent_fifo :: boolean()) :: :ok
  def run(%Resolved.Dlq{config: config, full_name: full_name, url: url}, parent_fifo?) do
    attrs =
      [message_retention_period: config.message_retention]
      |> maybe_put_fifo(parent_fifo?)

    case Sqs.create_queue(full_name, attrs) do
      {:ok, _} -> :ok
      {:error, {code, _}} when code in @existing_codes -> :ok
      {:error, reason} -> raise "failed to create DLQ #{full_name}: #{inspect(reason)}"
    end

    case Sqs.set_queue_attributes(url, attrs) do
      :ok -> :ok
      {:error, reason} -> raise "failed to set DLQ attributes on #{full_name}: #{inspect(reason)}"
    end
  end

  defp maybe_put_fifo(attrs, true), do: Keyword.put(attrs, :fifo_queue, true)
  defp maybe_put_fifo(attrs, _), do: attrs

end
