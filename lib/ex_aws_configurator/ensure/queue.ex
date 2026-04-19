defmodule ExAwsConfigurator.Ensure.Queue do
  @moduledoc false

  alias ExAwsConfigurator.Aws.Sqs
  alias ExAwsConfigurator.Ensure.Policy
  alias ExAwsConfigurator.Resolved

  @existing_codes ~w[QueueAlreadyExists QueueNameExists AWS.SimpleQueueService.QueueNameExists]

  @spec run(Resolved.Queue.t()) :: :ok
  def run(%Resolved.Queue{} = queue) do
    full_attrs = build_create_attrs(queue)

    case Sqs.create_queue(queue.full_name, full_attrs) do
      {:ok, _} -> :ok
      {:error, {code, _}} when code in @existing_codes -> :ok
      {:error, reason} -> raise "failed to create queue #{queue.full_name}: #{inspect(reason)}"
    end

    case Sqs.set_queue_attributes(queue.url, mutable_attrs(queue)) do
      :ok -> :ok
      {:error, reason} -> raise "failed to set attributes on #{queue.full_name}: #{inspect(reason)}"
    end
  end

  defp build_create_attrs(%Resolved.Queue{} = queue) do
    queue
    |> mutable_attrs()
    |> maybe_put_fifo(queue.config.fifo)
    |> maybe_put_content_dedup(queue.config)
  end

  defp mutable_attrs(%Resolved.Queue{} = queue) do
    [
      delay_seconds: queue.config.delay_seconds,
      maximum_message_size: queue.config.maximum_message_size,
      message_retention_period: queue.config.message_retention,
      receive_message_wait_time_seconds: queue.config.receive_message_wait_time,
      visibility_timeout: queue.config.visibility_timeout,
      policy: Policy.build(queue)
    ]
    |> maybe_put_redrive(queue.dlq, queue.config.dlq)
  end

  defp maybe_put_fifo(attrs, true), do: Keyword.put(attrs, :fifo_queue, true)
  defp maybe_put_fifo(attrs, _), do: attrs

  defp maybe_put_content_dedup(attrs, %{fifo: true, content_based_deduplication: dedup}),
    do: Keyword.put(attrs, :content_based_deduplication, dedup)

  defp maybe_put_content_dedup(attrs, _), do: attrs

  defp maybe_put_redrive(attrs, nil, _), do: attrs

  defp maybe_put_redrive(attrs, %Resolved.Dlq{arn: dlq_arn}, dlq_config) do
    policy =
      Jason.encode!(%{
        "deadLetterTargetArn" => dlq_arn,
        "maxReceiveCount" => dlq_config.max_receive_count
      })

    Keyword.put(attrs, :redrive_policy, policy)
  end

end
