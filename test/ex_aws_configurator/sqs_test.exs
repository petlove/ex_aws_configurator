defmodule ExAwsConfigurator.SQSTest do
  use ExAwsConfigurator.Case, async: true

  import ExUnit.CaptureLog

  alias ExAwsConfigurator.{Queue, QueueOptions, SNS, SQS}

  doctest SQS

  @moduletag capture_log: true

  describe "create_queue/2 with a struct" do
    test "creates the queue" do
      queue = build(:queue)

      assert capture_log(fn ->
               assert {:ok, %{status_code: 200}} = SQS.create_queue(queue)
             end) =~ "Queue #{Queue.full_name(queue)} created successfully"
    end

    test "creates the queue and its dead letter queue" do
      queue = build(:queue, options: %QueueOptions{dead_letter_queue: true})

      log =
        capture_log(fn ->
          assert {:ok, %{status_code: 200}} = SQS.create_queue(queue)
        end)

      assert log =~ "Queue #{Queue.full_name(queue)}_failures created successfully"
      assert log =~ "Queue #{Queue.full_name(queue)} created successfully"
    end

    test "does not create the queue when its dead letter queue cannot be created" do
      queue =
        build(:queue,
          options: %QueueOptions{dead_letter_queue: true, dead_letter_queue_suffix: "@failures"}
        )

      assert capture_log(fn ->
               assert {:error, {:http_error, 400, _}} = SQS.create_queue(queue)
             end) =~ "Error creating queue #{Queue.full_name(queue)}@failures"

      assert {:error, {:http_error, _, %{code: "AWS.SimpleQueueService.NonExistentQueue"}}} =
               SQS.send_message(queue, "message")
    end

    test "creates a queue with min attributes" do
      queue = build(:queue, prefix: nil, environment: nil)

      assert {:ok, %{status_code: 200}} = SQS.create_queue(queue)
    end

    test "creates a fifo queue with its dead letter queue" do
      queue = build(:fifo_queue, options: %QueueOptions{dead_letter_queue: true})

      log =
        capture_log(fn ->
          assert {:ok, %{status_code: 200}} = SQS.create_queue(queue)
        end)

      [name | _] = queue |> Queue.full_name() |> String.split(".")

      assert log =~ "Queue #{name}_failures.fifo created successfully"
      assert log =~ "Queue #{name}.fifo created successfully"
    end

    test "updates the queue when it already exists" do
      queue = build(:queue)

      assert {:ok, %{status_code: 200}} = SQS.create_queue(queue)

      assert capture_log(fn ->
               assert {:ok, %{status_code: 200}} = SQS.create_queue(queue)
             end) =~ "Queue #{Queue.full_name(queue)} updated successfully"
    end

    test "tags the queue" do
      queue = build(:queue)

      assert {:ok, %{status_code: 200}} = SQS.create_queue(queue, %{"team" => "platform"})
      assert {:ok, %{status_code: 200}} = SQS.create_queue(queue, %{"team" => "platform"})
    end

    test "does not create an invalid queue" do
      queue = build(:queue, name: :"!nv@l!d-N@me")

      assert capture_log(fn ->
               assert {:error, _} = SQS.create_queue(queue)
             end) =~ "Error creating queue"
    end
  end

  describe "create_queue/2 with an atom" do
    test "fetches the queue from the configuration and creates it" do
      assert {:ok, %{status_code: 200}} = SQS.create_queue(:another_queue)
    end

    test "raises when the queue is not configured" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SQS.create_queue(:not_configured_queue)
      end
    end
  end

  describe "subscribe/2" do
    setup do
      topic = build(:topic)
      {:ok, _} = SNS.create_topic(topic)

      queue = build(:queue, topics: [topic])
      {:ok, _} = SQS.create_queue(queue)

      %{queue: queue, topic: topic}
    end

    test "subscribes the queue to the topic", %{queue: queue, topic: topic} do
      assert {:ok, %{status_code: 200}} = SQS.subscribe(queue, topic)
    end

    test "sets raw message delivery when the queue asks for it", %{topic: topic} do
      queue =
        build(:queue, topics: [topic], options: %QueueOptions{raw_message_delivery: true})

      {:ok, _} = SQS.create_queue(queue)

      assert {:ok, %{status_code: 200}} = SQS.subscribe(queue, topic)
    end

    test "returns the AuthorizationError when the external topic owner did not allow it",
         %{queue: queue} do
      topic = build(:external_topic)

      assert capture_log(fn ->
               assert {:error, {:http_error, 403, %{code: "AuthorizationError"}}} =
                        SQS.subscribe(queue, topic)
             end) =~ "Not authorized to subscribe queue #{Queue.full_name(queue)}"
    end

    test "only warns when the external topic is configured with on_unauthorized: :warn",
         %{queue: queue} do
      topic = build(:external_topic, on_unauthorized: :warn)

      log =
        capture_log(fn ->
          assert {:ok, :unauthorized} = SQS.subscribe(queue, topic)
        end)

      assert log =~ "[warning]"
      assert log =~ "Ask the topic owner (account #{topic.account.id})"
      assert log =~ ~s("Action": [\n    "sns:Subscribe")
      assert log =~ ~s("AWS": "arn:aws:iam::000000000000:root")
    end

    test "accepts the configured names, in any combination", %{queue: queue, topic: topic} do
      assert {:ok, %{status_code: 200}} = SQS.subscribe(:an_queue, :an_topic)
      assert {:ok, %{status_code: 200}} = SQS.subscribe(queue, :an_topic)
      assert {:ok, %{status_code: 200}} = SQS.subscribe(:an_queue, topic)
    end

    test "raises when the queue is not configured" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SQS.subscribe(:not_configured_queue, :an_topic)
      end
    end

    test "raises when the topic is not configured" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SQS.subscribe(:an_queue, :not_configured_topic)
      end
    end
  end

  describe "send_message/3" do
    test "sends a message to an existent queue" do
      queue = build(:queue)
      {:ok, _} = SQS.create_queue(queue)

      assert {:ok, %{status_code: 200}} = SQS.send_message(queue, "message")
    end

    test "returns the error for a non existent queue" do
      assert {:error, {:http_error, _, %{code: "AWS.SimpleQueueService.NonExistentQueue"}}} =
               SQS.send_message(build(:queue), "message")
    end

    test "accepts the configured queue name" do
      {:ok, _} = SQS.create_queue(:an_queue)

      assert {:ok, %{status_code: 200}} = SQS.send_message(:an_queue, "message")
    end

    test "raises when the queue is not configured" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SQS.send_message(:not_configured_queue, "message")
      end
    end
  end
end
