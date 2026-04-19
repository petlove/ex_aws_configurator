defmodule ExAwsConfigurator.Ensure.PolicyTest do
  use ExUnit.Case, async: true

  alias ExAwsConfigurator.Config
  alias ExAwsConfigurator.Ensure.Policy
  alias ExAwsConfigurator.Resolved

  defp queue(opts \\ []) do
    policy = Keyword.get(opts, :policy)

    %Resolved.Queue{
      config: %Config.Queue{name: :q, policy: policy},
      arn: "arn:aws:sqs:us-east-1:1234:billing_q",
      subscribe_to_arns: ["arn:aws:sns:us-east-1:1234:billing_orders"]
    }
  end

  test "default policy grants sns.amazonaws.com sqs:SendMessage with ArnEquals guard" do
    doc = queue() |> Policy.build() |> Jason.decode!()

    assert doc["Version"] == "2012-10-17"
    assert [stmt] = doc["Statement"]
    assert stmt["Effect"] == "Allow"
    assert stmt["Principal"] == %{"Service" => "sns.amazonaws.com"}
    assert stmt["Action"] == "sqs:SendMessage"
    assert stmt["Resource"] == "arn:aws:sqs:us-east-1:1234:billing_q"

    assert stmt["Condition"] == %{
             "ArnEquals" => %{
               "aws:SourceArn" => ["arn:aws:sns:us-east-1:1234:billing_orders"]
             }
           }
  end

  test "user-provided :policy function fully replaces the default doc" do
    override = fn %{queue_arn: queue_arn, topic_arns: topic_arns} ->
      %{
        "Version" => "2012-10-17",
        "Statement" => [
          %{"Sid" => "Custom", "Resource" => queue_arn, "_topics" => topic_arns}
        ]
      }
    end

    doc = queue(policy: override) |> Policy.build() |> Jason.decode!()

    assert [%{"Sid" => "Custom"} = stmt] = doc["Statement"]
    assert stmt["Resource"] == "arn:aws:sqs:us-east-1:1234:billing_q"
    assert stmt["_topics"] == ["arn:aws:sns:us-east-1:1234:billing_orders"]
  end
end
