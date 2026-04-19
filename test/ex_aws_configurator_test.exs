defmodule ExAwsConfiguratorTest do
  use ExUnit.Case, async: false

  import Mox

  alias ExAwsConfigurator.{Config, Registry, Resolver}
  alias ExAwsConfigurator.Aws.{SnsMock, SqsMock}

  def forward_telemetry(_event, measurements, meta, pid) do
    send(pid, {:tele, measurements, meta})
  end

  setup :verify_on_exit!

  setup do
    raw = [
      queue_prefix: "billing",
      topics: [%{name: :orders}, %{name: :orders_fifo, fifo: true}],
      queues: [
        %{name: :orders_events, subscribe_to: [:orders]},
        %{name: :orders_fifo_events, fifo: true, subscribe_to: [:orders_fifo]}
      ]
    ]

    Config.load!(raw)
    |> Resolver.resolve(%{account_id: "1234", region: "us-east-1"})
    |> Registry.put!()

    on_exit(&Registry.reset/0)
    :ok
  end

  describe "publish/3" do
    test "looks up topic ARN and calls Sns.publish with the encoded payload" do
      expect(SnsMock, :publish, fn arn, message, _opts ->
        assert arn == "arn:aws:sns:us-east-1:1234:billing_orders"
        assert message == ~s({"id":1})
        {:ok, "msg-1"}
      end)

      assert {:ok, "msg-1"} = ExAwsConfigurator.publish(:orders, %{id: 1})
    end

    test "passes binary payload through untouched" do
      expect(SnsMock, :publish, fn _, "raw", _ -> {:ok, "id"} end)
      assert {:ok, "id"} = ExAwsConfigurator.publish(:orders, "raw")
    end

    test "raises for unknown topic" do
      assert_raise ArgumentError, ~r/unknown topic/, fn ->
        ExAwsConfigurator.publish(:nope, "x")
      end
    end

    test "raises when FIFO topic misses :message_group_id" do
      assert_raise ArgumentError, ~r/FIFO.*:message_group_id/, fn ->
        ExAwsConfigurator.publish(:orders_fifo, "x")
      end
    end

    test "FIFO passes when :message_group_id is present" do
      expect(SnsMock, :publish, fn _arn, _msg, opts ->
        assert Keyword.fetch!(opts, :message_group_id) == "g1"
        {:ok, "id"}
      end)

      assert {:ok, "id"} =
               ExAwsConfigurator.publish(:orders_fifo, "x", message_group_id: "g1")
    end

    test "emits telemetry :stop with :message_id on success" do
      expect(SnsMock, :publish, fn _, _, _ -> {:ok, "msg-42"} end)

      :telemetry.attach(
        "t-1",
        [:ex_aws_configurator, :publish, :stop],
        &__MODULE__.forward_telemetry/4,
        self()
      )

      ExAwsConfigurator.publish(:orders, "x")

      assert_received {:tele, %{duration: _}, %{topic: :orders, message_id: "msg-42"}}
      :telemetry.detach("t-1")
    end
  end

  describe "send_to_queue/3" do
    test "looks up queue URL and calls Sqs.send_message with encoded payload" do
      expect(SqsMock, :send_message, fn url, message, _opts ->
        assert url == "https://sqs.us-east-1.amazonaws.com/1234/billing_orders_events"
        assert message == ~s({"id":2})
        {:ok, "mid"}
      end)

      assert {:ok, "mid"} = ExAwsConfigurator.send_to_queue(:orders_events, %{id: 2})
    end

    test "raises when FIFO queue misses :message_group_id" do
      assert_raise ArgumentError, ~r/FIFO.*:message_group_id/, fn ->
        ExAwsConfigurator.send_to_queue(:orders_fifo_events, "x")
      end
    end
  end

  describe "publish_batch/2" do
    test "auto-generates entry ids and encodes payloads" do
      expect(SnsMock, :publish_batch, fn _arn, entries ->
        assert [
                 %{id: "msg_0", message: ~s({"i":1})},
                 %{id: "msg_1", message: ~s({"i":2}), message_group_id: "g1"}
               ] = entries

        {:ok, %{}}
      end)

      assert {:ok, _} =
               ExAwsConfigurator.publish_batch(:orders, [
                 %{payload: %{i: 1}},
                 %{payload: %{i: 2}, message_group_id: "g1"}
               ])
    end

    test "raises when batch entry is missing :payload" do
      assert_raise ArgumentError, ~r/missing :payload/, fn ->
        ExAwsConfigurator.publish_batch(:orders, [%{foo: :bar}])
      end
    end
  end

  describe "send_to_queue_batch/2" do
    test "uses :message_body key for SQS batch entries" do
      expect(SqsMock, :send_message_batch, fn _url, entries ->
        assert [%{id: "msg_0", message_body: "hello"}] = entries
        {:ok, %{}}
      end)

      assert {:ok, _} =
               ExAwsConfigurator.send_to_queue_batch(:orders_events, [%{payload: "hello"}])
    end
  end
end
