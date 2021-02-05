defmodule ExAwsConfiguratorTest do
  use ExAwsConfigurator.Case

  alias ExAwsConfigurator.{Queue, Topic}

  doctest ExAwsConfigurator

  @moduletag capture_log: true

  describe "setup/1" do
    test "setup all environment based on config" do
      config = [
        {
          :ex_aws_configurator,
          [
            account_id: "000000000000",
            queues: %{
              an_queue: %{
                environment: "test",
                prefix: "prefix",
                region: "us-east-1",
                topics: [:an_topic, :another_topic]
              }
            },
            topics: %{
              an_topic: %{environment: "test", prefix: "prefix", region: "us-east-1"},
              another_topic: %{environment: "teste", prefix: "prefixo", region: "sa-east-1"}
            }
          ]
        }
      ]

      Application.put_all_env(config)

      assert :ok == ExAwsConfigurator.setup()
    end
  end

  describe "get_env/1" do
    test "get application env value when system env is nil" do
      Application.put_all_env([{:ex_aws_configurator, [account_id: "000000000000"]}])

      assert "000000000000" = ExAwsConfigurator.get_env(:account_id)
    end

    test "get system application env when use :system tuple" do
      System.put_env("ACCOUNT_ID", "123456789101")
      Application.put_all_env([{:ex_aws_configurator, [account_id: {:system, "ACCOUNT_ID"}]}])

      assert "123456789101" = ExAwsConfigurator.get_env(:account_id)

      Application.put_all_env([{:ex_aws_configurator, [account_id: "000000000000"]}])
    end

    test "raise specific error when config do not exist" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        ExAwsConfigurator.get_env(:wrong)
      end
    end
  end

  describe "get_queue/1" do
    test "get queue configurations" do
      add_queue_to_config(build(:queue_config, name: :queue_name))

      assert %Queue{name: :queue_name} = ExAwsConfigurator.get_queue(:queue_name)
    end
  end

  describe "get_topic/1" do
    test "get topic configurations" do
      add_topic_to_config(build(:topic_config, name: :topic_name))

      assert %Topic{name: :topic_name} = ExAwsConfigurator.get_topic(:topic_name)
    end
  end
end
