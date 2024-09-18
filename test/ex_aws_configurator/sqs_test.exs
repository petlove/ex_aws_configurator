defmodule ExAwsConfigurator.SQSTest do
  use ExAwsConfigurator.Case

  import ExUnit.CaptureLog

  alias ExAwsConfigurator.{Queue, SNS, SQS}

  doctest SQS

  @moduletag capture_log: true

  setup do
    add_queue_to_config(build(:queue_config, name: :queue_name))
    add_queue_to_config(%{queue_min_config: %{}})
    add_topic_to_config(build(:topic_config, name: :topic_name))
    add_queue_to_config(build(:queue_config, name: :raw_queue, raw_message_delivery: true))
    add_queue_to_config(build(:queue_config, name: :"!nv@l!d-N@me"))

    add_queue_to_config(
      build(:queue_config,
        name: :"queue.fifo",
        content_based_deduplication: true,
        fifo_queue: true
      )
    )

    add_queue_to_config(
      build(:queue_config, name: :without_failures_queue, dead_letter_queue: false)
    )

    SQS.create_queue(:queue_name)
    SNS.create_topic(:topic_name)
    SQS.create_queue(:raw_queue)

    add_queue_to_config(build(:queue_config, name: :non_created_queue))
  end

  describe "create_queue/1" do
    test "create queue when receive a atom with correct configuration" do
      assert capture_log(fn ->
               assert {:ok, %{status_code: 200}} = SQS.create_queue(:queue_name)
             end) =~ "created successfully"
    end

    test "create queue without dead letter queue" do
      assert capture_log(fn ->
               assert {:ok, %{status_code: 200}} = SQS.create_queue(:without_failures_queue)
             end) =~ "created successfully"
    end

    test "create queue with min attributes" do
      assert capture_log(fn ->
               assert {:ok, %{status_code: 200}} = SQS.create_queue(:queue_min_config)
             end) =~ "created successfully"
    end

    test "create a fifo queue" do
      assert capture_log(fn ->
               assert {:ok, %{status_code: 200}} = SQS.create_queue(:"queue.fifo")

               queue = ExAwsConfigurator.get_queue(:"queue.fifo")

               assert %{attributes: %{content_based_deduplication: true, fifo_queue: true}} =
                        queue

               assert Queue.full_name(queue) == "prefix_test_queue.fifo"
             end) =~ "created successfully"
    end

    test "do not create an invalid queue" do
      assert capture_log(fn ->
               assert {:error, _} = SQS.create_queue(:"!nv@l!d-N@me")
             end) =~ "Error creating queue"
    end

    test "raise when tries to create a queue without configuration" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SQS.create_queue(:not_configured_queue)
      end
    end
  end

  describe "subscribe/2" do
    test "subscribe queue to an topic when is atom and with valid configuration" do
      assert {:ok, %{status_code: 200}} = SQS.subscribe(:queue_name, :topic_name)
    end

    test "subscribe queue to an topic when raw_message_delivery is true" do
      assert {:ok, %{status_code: 200}} = SQS.subscribe(:raw_queue, :topic_name)
    end

    test "raise when tries to subscribe a queue without queue configuration" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SQS.subscribe(:not_configured_queue, :topic_name)
      end
    end

    test "raise when tries to subscribe a topic without configuration" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SQS.subscribe(:queue_name, :not_configured_topic)
      end
    end
  end

  describe "send_message/2" do
    test "send an message to an existent queue" do
      assert {:ok, %{status_code: 200}} = SQS.send_message(:queue_name, "message")
    end

    test "public an message to an non existent queue" do
      assert {:error, {:http_error, _, %{code: "AWS.SimpleQueueService.NonExistentQueue"}}} =
               SQS.send_message(:non_created_queue, "message")
    end

    test "raise when tries to publish into an no configured queue" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SQS.send_message(:not_configured_queue, "message")
      end
    end
  end
end
