defmodule ExAwsConfigurator.TelemetryTest do
  use ExAwsConfigurator.Case, async: true

  alias ExAwsConfigurator.{Queue, SNS, SQS, Telemetry, Topic}

  @moduletag capture_log: true

  @operations [:publish, :send_message, :create_topic, :create_queue, :subscribe, :setup]
  @events for operation <- @operations,
              suffix <- [:start, :stop, :exception],
              do: [:ex_aws_configurator, operation, suffix]

  # Every test attaches its own handler; events are forwarded only when emitted by the
  # test process, so the async tests do not see each other's spans.
  setup %{test: test} do
    handler_id = {__MODULE__, test}
    test_pid = self()

    :telemetry.attach_many(
      handler_id,
      @events,
      fn event, measurements, metadata, _config ->
        if self() == test_pid, do: send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  describe "publish/3" do
    test "emits start and stop with the topic metadata" do
      topic = build(:topic)
      {:ok, _} = SNS.create_topic(topic)

      assert {:ok, _} = SNS.publish(topic, "message")

      assert_receive {:telemetry, [:ex_aws_configurator, :publish, :start], %{system_time: _},
                      %{topic: name}}

      assert_receive {:telemetry, [:ex_aws_configurator, :publish, :stop], %{duration: duration},
                      %{topic: ^name, result: :ok} = metadata}

      assert name == topic.name
      assert is_integer(duration)

      assert Map.delete(metadata, :telemetry_span_context) == %{
               topic: topic.name,
               topic_arn: Topic.arn(topic),
               region: "us-east-1",
               account: :default,
               result: :ok
             }
    end

    test "stop carries the error returned by AWS" do
      topic = build(:topic)

      assert {:error, reason} = SNS.publish(topic, "message")

      assert_receive {:telemetry, [:ex_aws_configurator, :publish, :stop], _,
                      %{result: :error, error: ^reason}}

      assert {:http_error, 404, _} = reason
    end
  end

  describe "send_message/3" do
    test "emits start and stop with the queue metadata" do
      queue = build(:queue)
      {:ok, _} = SQS.create_queue(queue)

      assert {:ok, _} = SQS.send_message(queue, "message")

      assert_receive {:telemetry, [:ex_aws_configurator, :send_message, :start], _, %{queue: _}}

      assert_receive {:telemetry, [:ex_aws_configurator, :send_message, :stop], %{duration: _},
                      metadata}

      assert Map.delete(metadata, :telemetry_span_context) == %{
               queue: queue.name,
               queue_arn: Queue.arn(queue),
               region: "us-east-1",
               account: :default,
               result: :ok
             }
    end
  end

  describe "setup spans" do
    test "create_topic emits a span even for an external topic" do
      topic = build(:external_topic)

      assert {:ok, :external} = SNS.create_topic(topic)

      assert_receive {:telemetry, [:ex_aws_configurator, :create_topic, :stop], _,
                      %{topic: name, account: :external, result: :ok}}

      assert name == topic.name
    end

    test "create_queue emits one span for the queue and one for its dead letter queue" do
      queue = build(:queue, options: %ExAwsConfigurator.QueueOptions{dead_letter_queue: true})
      dead_letter_queue = Queue.dead_letter_queue(queue)

      assert {:ok, _} = SQS.create_queue(queue)

      assert_receive {:telemetry, [:ex_aws_configurator, :create_queue, :stop], _,
                      %{queue: dlq_name, result: :ok}}

      assert_receive {:telemetry, [:ex_aws_configurator, :create_queue, :stop], _,
                      %{queue: name, result: :ok}}

      assert dlq_name == dead_letter_queue.name
      assert name == queue.name
    end

    test "subscribe emits a span with both resources" do
      topic = build(:topic)
      queue = build(:queue, topics: [topic])
      {:ok, _} = SNS.create_topic(topic)
      {:ok, _} = SQS.create_queue(queue)

      assert {:ok, _} = SQS.subscribe(queue, topic)

      assert_receive {:telemetry, [:ex_aws_configurator, :subscribe, :stop], _, metadata}

      assert Map.delete(metadata, :telemetry_span_context) == %{
               queue: queue.name,
               topic: topic.name,
               queue_arn: Queue.arn(queue),
               topic_arn: Topic.arn(topic),
               region: "us-east-1",
               result: :ok
             }
    end

    test "setup emits a span with the result" do
      assert :ok = ExAwsConfigurator.setup()

      assert_receive {:telemetry, [:ex_aws_configurator, :setup, :start], _, %{}}
      assert_receive {:telemetry, [:ex_aws_configurator, :setup, :stop], _, %{result: :ok}}
    end
  end

  describe "span/3" do
    test "emits exception when the call raises" do
      assert_raise RuntimeError, "boom", fn ->
        Telemetry.span(:publish, %{topic: :an_topic}, fn -> raise "boom" end)
      end

      assert_receive {:telemetry, [:ex_aws_configurator, :publish, :exception], %{duration: _},
                      %{topic: :an_topic, kind: :error, reason: %RuntimeError{}}}

      refute_receive {:telemetry, [:ex_aws_configurator, :publish, :stop], _, _}
    end

    test "names the failed phase on a setup error" do
      assert {:error, :queues} = Telemetry.span(:setup, %{}, fn -> {:error, :queues} end)

      assert_receive {:telemetry, [:ex_aws_configurator, :setup, :stop], _,
                      %{result: :error, error: :queues}}
    end
  end

  describe "metrics/1" do
    test "returns the definitions named under the prefix" do
      metrics = Telemetry.metrics("my_app")

      assert Enum.map(metrics, &Enum.join(&1.name, ".")) == [
               "my_app.sns.publish.count",
               "my_app.sns.publish.duration",
               "my_app.sns.publish.exception.count",
               "my_app.sqs.send_message.count",
               "my_app.sqs.send_message.duration",
               "my_app.sqs.send_message.exception.count",
               "my_app.setup.count",
               "my_app.setup.duration"
             ]

      assert Enum.all?(metrics, &(&1.event_name in @events))

      assert %Elixir.Telemetry.Metrics.Counter{
               event_name: [:ex_aws_configurator, :publish, :stop],
               tags: [:topic, :result]
             } = Enum.at(metrics, 0)

      assert %Elixir.Telemetry.Metrics.Distribution{
               event_name: [:ex_aws_configurator, :send_message, :stop],
               unit: :millisecond,
               tags: [:queue, :result]
             } = Enum.at(metrics, 4)

      assert %Elixir.Telemetry.Metrics.Counter{
               event_name: [:ex_aws_configurator, :setup, :stop],
               tags: [:result]
             } = Enum.at(metrics, 6)
    end

    test "accepts an atom prefix" do
      assert [%{name: [:my_app, :sns, :publish, :count]} | _] = Telemetry.metrics(:my_app)
    end
  end
end
