defmodule ExAwsConfigurator.ResolverTest do
  use ExUnit.Case, async: true

  alias ExAwsConfigurator.{Config, Resolver}

  @identity %{account_id: "1234", region: "us-east-1"}

  defp build(raw), do: Config.load!(raw) |> Resolver.resolve(@identity)

  test "local topic ARN uses current identity + prefix" do
    resolved =
      build(
        queue_prefix: "billing",
        topics: [%{name: :orders}],
        queues: []
      )

    assert resolved.topics[:orders].arn ==
             "arn:aws:sns:us-east-1:1234:billing_orders"
  end

  test "FIFO suffix is appended to full_name" do
    resolved =
      build(
        queue_prefix: "billing",
        topics: [%{name: :orders, fifo: true}],
        queues: []
      )

    assert resolved.topics[:orders].full_name == "billing_orders.fifo"
    assert resolved.topics[:orders].arn =~ ".fifo"
  end

  test "external topic with :arn uses it literally" do
    arn = "arn:aws:sns:us-west-2:9999:other-topic"

    resolved =
      build(
        queue_prefix: "billing",
        external_topics: [%{name: :partner, arn: arn}],
        queues: []
      )

    assert resolved.external_topics[:partner].arn == arn
  end

  test "external topic with :prefix inherits current account + region" do
    resolved =
      build(
        queue_prefix: "billing",
        external_topics: [%{name: :shipment_updates, prefix: "shipping"}],
        queues: []
      )

    assert resolved.external_topics[:shipment_updates].arn ==
             "arn:aws:sns:us-east-1:1234:shipping_shipment_updates"
  end

  test "external topic overrides account_id and region when given" do
    resolved =
      build(
        queue_prefix: "billing",
        external_topics: [
          %{name: :customer_events, prefix: "crm", account_id: "9999", region: "us-west-2"}
        ],
        queues: []
      )

    assert resolved.external_topics[:customer_events].arn ==
             "arn:aws:sns:us-west-2:9999:crm_customer_events"
  end

  test "queue subscribe_to_arns resolves local + external names" do
    resolved =
      build(
        queue_prefix: "billing",
        topics: [%{name: :orders}],
        external_topics: [%{name: :shipment_updates, prefix: "shipping"}],
        queues: [%{name: :orders_events, subscribe_to: [:orders, :shipment_updates]}]
      )

    assert resolved.queues[:orders_events].subscribe_to_arns == [
             "arn:aws:sns:us-east-1:1234:billing_orders",
             "arn:aws:sns:us-east-1:1234:shipping_shipment_updates"
           ]
  end

  test "DLQ inherits FIFO-ness from parent and gets _failures suffix" do
    resolved =
      build(
        queue_prefix: "billing",
        topics: [%{name: :t, fifo: true}],
        queues: [%{name: :events, fifo: true, subscribe_to: [:t]}]
      )

    queue = resolved.queues[:events]
    assert queue.dlq.full_name == "billing_events_failures.fifo"
    assert queue.dlq.arn =~ "billing_events_failures.fifo"
  end

  test "dlq: false yields nil resolved dlq" do
    resolved =
      build(
        queue_prefix: "billing",
        topics: [%{name: :t}],
        queues: [%{name: :q, dlq: false, subscribe_to: [:t]}]
      )

    assert is_nil(resolved.queues[:q].dlq)
  end

  test "queue URL uses standard AWS SQS URL shape" do
    resolved =
      build(
        queue_prefix: "billing",
        topics: [%{name: :t}],
        queues: [%{name: :q, subscribe_to: [:t]}]
      )

    assert resolved.queues[:q].url == "https://sqs.us-east-1.amazonaws.com/1234/billing_q"
  end
end
