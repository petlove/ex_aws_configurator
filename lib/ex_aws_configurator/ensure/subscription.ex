defmodule ExAwsConfigurator.Ensure.Subscription do
  @moduledoc false

  alias ExAwsConfigurator.Aws.Sns
  alias ExAwsConfigurator.Resolved

  @spec run(Resolved.Queue.t()) :: :ok
  def run(%Resolved.Queue{} = queue) do
    Enum.each(queue.subscribe_to_arns, fn topic_arn ->
      ensure_one(topic_arn, queue)
    end)
  end

  defp ensure_one(topic_arn, queue) do
    sub_arn =
      case existing_subscription(topic_arn, queue.arn) do
        {:ok, arn} ->
          arn

        :missing ->
          case Sns.subscribe(topic_arn, queue.arn, %{}) do
            {:ok, arn} ->
              arn

            {:error, reason} ->
              raise "failed to subscribe #{queue.full_name} to #{topic_arn}: #{inspect(reason)}"
          end
      end

    apply_raw_delivery(sub_arn, queue.config.raw_message_delivery)
  end

  defp existing_subscription(topic_arn, queue_arn) do
    case Sns.list_subscriptions_by_topic(topic_arn) do
      {:ok, subs} ->
        case Enum.find(subs, &(&1.endpoint == queue_arn)) do
          nil -> :missing
          %{subscription_arn: arn} -> {:ok, arn}
        end

      {:error, reason} ->
        raise "failed to list subscriptions for #{topic_arn}: #{inspect(reason)}"
    end
  end

  # Pending subscriptions (e.g. just created, not confirmed) have "PendingConfirmation"
  # as the ARN — can't set attributes on those. SQS subscriptions are auto-confirmed,
  # so in practice we always get a real ARN.
  defp apply_raw_delivery("PendingConfirmation", _), do: :ok
  defp apply_raw_delivery(_arn, false), do: :ok

  defp apply_raw_delivery(arn, true) do
    case Sns.set_subscription_attribute(arn, "RawMessageDelivery", "true") do
      :ok -> :ok
      {:error, reason} -> raise "failed to set RawMessageDelivery on #{arn}: #{inspect(reason)}"
    end
  end
end
