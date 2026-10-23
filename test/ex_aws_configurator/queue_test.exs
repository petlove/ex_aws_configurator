defmodule ExAwsConfigurator.QueueTest do
  use ExAwsConfigurator.Case, async: true

  alias ExAwsConfigurator.{Queue, QueueAttributes, QueueOptions}

  doctest Queue

  setup do
    queue =
      build(:queue, %{
        region: "reg",
        prefix: "pref",
        environment: "env",
        name: :queue
      })

    {:ok, %{queue: queue}}
  end

  describe "arn/1" do
    test "build arn from queue", %{queue: queue} do
      assert "arn:aws:sqs:reg:000000000000:pref_env_queue" = Queue.arn(queue)
    end
  end

  describe "full_name/1" do
    test "build full_name from queue", %{queue: queue} do
      assert "pref_env_queue" = Queue.full_name(queue)
    end

    test "uses custom separator when configured", %{queue: queue} do
      queue = %{queue | separator: "-"}
      assert "pref-env-queue" = Queue.full_name(queue)
    end
  end

  describe "url/1" do
    test "build url from queue", %{queue: queue} do
      assert Queue.url(queue) =~ "000000000000/pref_env_queue"
    end
  end

  describe "dead_letter_queue/1" do
    test "derives a queue named after the queue plus the suffix, without policies or topics" do
      queue =
        build(:queue,
          name: :orders,
          topics: [build(:topic)],
          options: %QueueOptions{dead_letter_queue: true, dead_letter_queue_suffix: "_dlq"}
        )

      dlq = Queue.dead_letter_queue(queue)

      assert %Queue{
               name: "orders_dlq",
               prefix: "prefix",
               environment: "test",
               region: "us-east-1",
               account: %{id: "000000000000"},
               topics: [],
               options: %QueueOptions{dead_letter_queue: false},
               attributes: %QueueAttributes{policy: nil, redrive_policy: nil}
             } = dlq

      assert Queue.full_name(dlq) == "prefix_test_orders_dlq"
      assert Queue.arn(dlq) == "arn:aws:sqs:us-east-1:000000000000:prefix_test_orders_dlq"
    end

    test "keeps the .fifo suffix at the end and the fifo attributes" do
      queue =
        build(:fifo_queue, name: :"orders.fifo", options: %QueueOptions{dead_letter_queue: true})

      dlq = Queue.dead_letter_queue(queue)

      assert dlq.name == "orders_failures.fifo"

      assert %QueueAttributes{fifo_queue: true, content_based_deduplication: true} =
               dlq.attributes
    end
  end

  describe "redrive_policy/1" do
    test "points to the dead letter queue arn with the max receive count" do
      queue =
        build(:queue,
          name: :orders,
          options: %QueueOptions{dead_letter_queue: true, max_receive_count: 3}
        )

      assert %{"maxReceiveCount" => 3, "deadLetterTargetArn" => arn} =
               queue |> Queue.redrive_policy() |> Jason.decode!()

      assert arn == Queue.arn(Queue.dead_letter_queue(queue))
    end

    test "is nil when the queue has no dead letter queue" do
      assert nil == Queue.redrive_policy(build(:queue))
    end
  end

  describe "default attributes and options" do
    test "QueueAttributes defaults" do
      assert struct(QueueAttributes) == %QueueAttributes{
               content_based_deduplication: nil,
               delay_seconds: 0,
               fifo_queue: nil,
               maximum_message_size: 262_144,
               message_retention_period: 1_209_600,
               receive_message_wait_time_seconds: 0,
               policy: nil,
               redrive_policy: nil,
               visibility_timeout: 60
             }
    end

    test "QueueOptions defaults" do
      assert struct(QueueOptions) == %QueueOptions{
               max_receive_count: 7,
               dead_letter_queue: true,
               dead_letter_queue_suffix: "_failures",
               raw_message_delivery: false
             }
    end
  end
end
