defmodule ExAwsConfigurator.QueueTest do
  use ExAwsConfigurator.Case

  alias ExAwsConfigurator.{Queue, QueueAttributes, QueueOptions}

  doctest Queue

  setup do
    queue =
      build(:queue, %{
        region: "reg",
        prefix: "pref",
        environment: "env",
        name: "topic"
      })

    {:ok, %{queue: queue}}
  end

  describe "arn/1" do
    test "build arn from queue", %{queue: queue} do
      assert "arn:aws:sqs:reg:000000000000:pref_env_topic" = Queue.arn(queue)
    end
  end

  describe "full_name/1" do
    test "build full_name from queue", %{queue: queue} do
      assert "pref_env_topic" = Queue.full_name(queue)
    end

    test "uses custom separator when configured", %{queue: queue} do
      queue = %{queue | separator: "-"}
      assert "pref-env-topic" = Queue.full_name(queue)
    end
  end

  describe "url/1" do
    test "build url from queue", %{queue: queue} do
      assert Queue.url(queue) =~ "000000000000/pref_env_topic"
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
