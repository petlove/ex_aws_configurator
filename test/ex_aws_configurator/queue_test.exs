defmodule ExAwsConfigurator.QueueTest do
  use ExAwsConfigurator.Case, async: true

  alias ExAwsConfigurator.Queue

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
  end

  describe "url/1" do
    test "build url from queue", %{queue: queue} do
      assert "http://localhost/000000000000/pref_env_topic" = Queue.url(queue)
    end
  end
end
