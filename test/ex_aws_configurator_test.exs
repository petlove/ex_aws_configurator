defmodule ExAwsConfiguratorTest do
  use ExAwsConfigurator.Case

  alias ExAwsConfigurator.{Queue, Topic}

  doctest ExAwsConfigurator

  @app :ex_aws_configurator
  @moduletag capture_log: true

  setup do
    previous = Application.get_all_env(@app)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(@app), do: Application.delete_env(@app, key)
      Application.put_all_env([{@app, previous}])
    end)

    :ok
  end

  defp put_config(overrides) do
    config =
      Keyword.merge(
        [
          environment: :test,
          account_id: "000000000000",
          region: "us-east-1",
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
            another_topic: %{environment: nil, region: "sa-east-1"}
          }
        ],
        overrides
      )

    Application.put_all_env([{@app, config}])
  end

  describe "setup/0" do
    test "setup all environment based on config" do
      put_config([])

      assert :ok == ExAwsConfigurator.setup()
    end

    test "fails before touching AWS when the configuration is invalid" do
      put_config(queues: %{orphan: %{topics: [:missing_topic]}})

      assert_raise ExAwsConfigurator.NoResultsError, fn -> ExAwsConfigurator.setup() end
    end
  end

  describe "setup!/0" do
    test "not raise an error when everything goes as it should" do
      put_config([])

      assert :ok == ExAwsConfigurator.setup!()
    end

    test "when something goes wrong when creating the topics, it is expected to raise appropriate error" do
      put_config(
        queues: %{},
        topics: %{:"&invalid-topic-n@-m{e}" => %{environment: "test", prefix: "prefix"}}
      )

      assert_raise ExAwsConfigurator.SetupError,
                   ~r/something went wrong when creating the topics/,
                   fn -> ExAwsConfigurator.setup!() end
    end

    test "when something goes wrong when creating the queues, it is expected to raise appropriate error" do
      put_config(
        queues: %{:"&invalid-queue-n@-m{e}" => %{environment: "test", prefix: "prefix"}},
        topics: %{}
      )

      assert_raise ExAwsConfigurator.SetupError,
                   ~r/something went wrong when creating the queues/,
                   fn -> ExAwsConfigurator.setup!() end
    end
  end

  describe "setup/0 with external topics" do
    setup do
      put_config(
        accounts: %{
          external: %{id: ExAwsConfigurator.HttpStub.external_account_id(), region: "sa-east-1"}
        },
        queues: %{
          an_queue: %{
            environment: "test",
            prefix: "prefix",
            region: "us-east-1",
            topics: [:an_topic, :their_topic]
          }
        },
        topics: %{
          an_topic: %{environment: "test", prefix: "prefix", region: "us-east-1"},
          their_topic: %{environment: "test", prefix: "theirs", account: :external}
        }
      )

      :ok
    end

    test "fails on subscriptions when the external topic owner did not allow it" do
      assert {:error, :subscriptions} = ExAwsConfigurator.setup()

      assert_raise ExAwsConfigurator.SetupError,
                   ~r/subscribing the queues to the topics/,
                   fn -> ExAwsConfigurator.setup!() end
    end

    test "succeeds when the external topic is configured with on_unauthorized: :warn" do
      add_topic_to_config(%{
        their_topic: %{
          environment: "test",
          prefix: "theirs",
          account: :external,
          on_unauthorized: :warn
        }
      })

      assert :ok = ExAwsConfigurator.setup()
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

  describe "get_account/1" do
    test "get the default account" do
      assert %ExAwsConfigurator.Account{name: :default, id: "000000000000"} =
               ExAwsConfigurator.get_account(:default)
    end
  end
end
