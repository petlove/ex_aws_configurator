defmodule ExAwsConfigurator.Ensure.Policy do
  @moduledoc false

  alias ExAwsConfigurator.Resolved

  @spec build(Resolved.Queue.t()) :: String.t()
  def build(%Resolved.Queue{config: %{policy: fun}} = queue) when is_function(fun, 1) do
    fun.(%{queue_arn: queue.arn, topic_arns: queue.subscribe_to_arns})
    |> Jason.encode!()
  end

  def build(%Resolved.Queue{} = queue) do
    %{
      "Version" => "2012-10-17",
      "Statement" => [
        %{
          "Sid" => "AllowSNSPublish",
          "Effect" => "Allow",
          "Principal" => %{"Service" => "sns.amazonaws.com"},
          "Action" => "sqs:SendMessage",
          "Resource" => queue.arn,
          "Condition" => %{"ArnEquals" => %{"aws:SourceArn" => queue.subscribe_to_arns}}
        }
      ]
    }
    |> Jason.encode!()
  end
end
