defmodule ExAwsConfigurator.ConfigTest do
  use ExAwsConfigurator.Case

  alias ExAwsConfigurator.{Account, Config, HttpStub, Queue, Topic}

  @app :ex_aws_configurator
  @external_id HttpStub.external_account_id()

  setup do
    previous = Application.get_all_env(@app)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(@app), do: Application.delete_env(@app, key)
      Application.put_all_env([{@app, previous}])
    end)

    add_external_account_to_config()
    :ok
  end

  describe "get_account/1" do
    test ":default is built from the global account_id and region" do
      assert %Account{name: :default, id: "000000000000", region: "us-east-1"} =
               Config.get_account(:default)
    end

    test "resolves {:system, var} on the global account_id and region" do
      System.put_env("TEST_ACCOUNT_ID", "123456789101")
      System.put_env("TEST_REGION", "eu-west-1")
      Application.put_env(@app, :account_id, {:system, "TEST_ACCOUNT_ID"})
      Application.put_env(@app, :region, {:system, "TEST_REGION"})

      assert %Account{id: "123456789101", region: "eu-west-1"} = Config.get_account(:default)
    end

    test "returns a named account with its own region" do
      assert %Account{name: :external, id: @external_id, region: "sa-east-1"} =
               ExAwsConfigurator.get_account(:external)
    end

    test "falls back to the global region and resolves {:system, var} ids" do
      System.put_env("OTHER_ACCOUNT_ID", "111111111111")

      Application.put_env(@app, :accounts, other: [id: {:system, "OTHER_ACCOUNT_ID"}])

      assert %Account{name: :other, id: "111111111111", region: "us-east-1"} =
               Config.get_account(:other)
    end

    test "raises when the account is not configured" do
      assert_raise ExAwsConfigurator.NoResultsError, ~r/account `unknown`/, fn ->
        Config.get_account(:unknown)
      end
    end

    test "raises when the account has no id" do
      Application.put_env(@app, :accounts, %{broken: %{region: "sa-east-1"}})

      assert_raise ArgumentError, ~r/must have an :id/, fn -> Config.get_account(:broken) end
    end
  end

  describe "get_topic/1" do
    test "a topic without account belongs to the default account and is not external" do
      add_topic_to_config(%{own_topic: %{prefix: "prefix", environment: "test"}})

      topic = Config.get_topic(:own_topic)

      assert %Topic{external: false, account: %Account{name: :default}, region: "us-east-1"} =
               topic

      assert Topic.arn(topic) == "arn:aws:sns:us-east-1:000000000000:prefix_test_own_topic"
    end

    test "a topic of another account is external and uses the account region and id" do
      add_topic_to_config(%{
        their_topic: %{prefix: "health_api", environment: "test", account: :external}
      })

      topic = Config.get_topic(:their_topic)

      assert %Topic{external: true, account: %Account{name: :external}, region: "sa-east-1"} =
               topic

      assert Topic.arn(topic) ==
               "arn:aws:sns:sa-east-1:#{@external_id}:health_api_test_their_topic"
    end

    test "the topic region still overrides the account region" do
      add_topic_to_config(%{regional: %{account: :external, region: "us-east-2"}})

      assert %Topic{region: "us-east-2"} = Config.get_topic(:regional)
    end

    test "a raw arn is used as is and marks the topic external when owned by another account" do
      arn = "arn:aws:sns:sa-east-1:#{@external_id}:legacy-name"
      add_topic_to_config(%{legacy: %{arn: arn}})

      topic = Config.get_topic(:legacy)

      assert %Topic{external: true, region: "sa-east-1", account: %Account{id: @external_id}} =
               topic

      assert Topic.arn(topic) == arn
    end

    test "a raw arn of the default account is not external" do
      add_topic_to_config(%{own_legacy: %{arn: "arn:aws:sns:us-east-1:000000000000:legacy"}})

      assert %Topic{external: false} = Config.get_topic(:own_legacy)
    end

    test "raises on an invalid raw arn" do
      add_topic_to_config(%{bad_arn: %{arn: "not-an-arn"}})

      assert_raise ArgumentError, ~r/invalid SNS topic arn/, fn -> Config.get_topic(:bad_arn) end
    end

    test "on_unauthorized defaults to :error, can be set globally and per topic" do
      add_topic_to_config(%{
        t1: %{account: :external},
        t2: %{account: :external, on_unauthorized: :warn}
      })

      assert %Topic{on_unauthorized: :error} = Config.get_topic(:t1)
      assert %Topic{on_unauthorized: :warn} = Config.get_topic(:t2)

      Application.put_env(@app, :on_unauthorized, :warn)
      assert %Topic{on_unauthorized: :warn} = Config.get_topic(:t1)
    end

    test "raises on an invalid on_unauthorized" do
      add_topic_to_config(%{t3: %{account: :external, on_unauthorized: :ignore}})

      assert_raise ArgumentError, ~r/invalid :on_unauthorized/, fn -> Config.get_topic(:t3) end
    end

    test "raises when the topic is not configured" do
      assert_raise ExAwsConfigurator.NoResultsError, ~r/topic `nope`/, fn ->
        Config.get_topic(:nope)
      end
    end
  end

  describe "get_queue/1" do
    test "the queue belongs to the default account and carries its topics" do
      queue = Config.get_queue(:an_queue)

      assert %Queue{account: %Account{name: :default, id: "000000000000"}} = queue
      assert Queue.arn(queue) == "arn:aws:sqs:us-east-1:000000000000:prefix_test_an_queue"
      assert [%Topic{name: :an_topic}, %Topic{name: :another_topic}] = queue.topics
    end

    test "the queue policy allows the external topic arn" do
      add_topic_to_config(%{
        their_topic: %{prefix: "health_api", environment: "test", account: :external}
      })

      add_queue_to_config(%{
        my_queue: %{prefix: "prefix", environment: "test", topics: [:their_topic]}
      })

      queue = Config.get_queue(:my_queue)

      assert %{"Statement" => [%{"Condition" => %{"ArnLike" => %{"aws:SourceArn" => arns}}}]} =
               Jason.decode!(queue.attributes.policy)

      assert arns == ["arn:aws:sns:sa-east-1:#{@external_id}:health_api_test_their_topic"]
    end

    test "raises when the queue subscribes to a topic that is not configured" do
      add_queue_to_config(%{orphan: %{topics: [:missing_topic]}})

      assert_raise ExAwsConfigurator.NoResultsError, ~r/topic `missing_topic`/, fn ->
        Config.get_queue(:orphan)
      end
    end

    test "raises when the queue is not configured" do
      assert_raise ExAwsConfigurator.NoResultsError, ~r/queue `nope`/, fn ->
        Config.get_queue(:nope)
      end
    end
  end

  describe "load/0" do
    test "builds every account, topic and queue at once" do
      add_topic_to_config(%{their_topic: %{prefix: "theirs", account: :external}})

      assert %Config{accounts: accounts, topics: topics, queues: queues} = Config.load()

      assert %{default: %Account{name: :default}, external: %Account{name: :external}} =
               accounts

      assert %{an_topic: %Topic{}, another_topic: %Topic{}, their_topic: %Topic{external: true}} =
               topics

      assert %{an_queue: %Queue{topics: [%Topic{name: :an_topic}, _]}, another_queue: %Queue{}} =
               queues
    end

    test "works with an empty configuration" do
      Application.put_env(@app, :topics, %{})
      Application.put_env(@app, :queues, %{})
      Application.delete_env(@app, :accounts)

      assert %Config{accounts: %{default: %Account{}}, topics: %{}, queues: %{}} = Config.load()
    end

    test "fails before touching AWS when a queue points to a missing topic" do
      add_queue_to_config(%{orphan: %{topics: [:missing_topic]}})

      assert_raise ExAwsConfigurator.NoResultsError, ~r/topic `missing_topic`/, fn ->
        Config.load()
      end
    end

    test "fails before touching AWS when an account has no id" do
      Application.put_env(@app, :accounts, %{broken: %{region: "sa-east-1"}})

      assert_raise ArgumentError, ~r/`broken` must have an :id/, fn -> Config.load() end
    end
  end
end
