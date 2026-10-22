defmodule ExAwsConfigurator.ConfigTest do
  use ExAwsConfigurator.Case

  alias ExAwsConfigurator.{Account, Config, HttpStub, Queue, Topic}

  @external_id HttpStub.external_account_id()

  setup do
    previous_accounts = Application.get_env(:ex_aws_configurator, :accounts)
    previous_mode = Application.get_env(:ex_aws_configurator, :on_unauthorized)

    on_exit(fn ->
      Application.put_env(:ex_aws_configurator, :accounts, previous_accounts || %{})
      Application.delete_env(:ex_aws_configurator, :on_unauthorized)

      if previous_mode,
        do: Application.put_env(:ex_aws_configurator, :on_unauthorized, previous_mode)
    end)

    add_external_account_to_config()
    :ok
  end

  describe "default_account/0" do
    test "is built from the global account_id and region" do
      assert %Account{name: :default, id: "000000000000", region: "us-east-1"} =
               Config.default_account()
    end
  end

  describe "get_account/1" do
    test ":default returns the default account" do
      assert Config.get_account(:default) == Config.default_account()
    end

    test "returns a named account with its own region" do
      assert %Account{name: :external, id: @external_id, region: "sa-east-1"} =
               ExAwsConfigurator.get_account(:external)
    end

    test "falls back to the global region and resolves {:system, var} ids" do
      System.put_env("OTHER_ACCOUNT_ID", "111111111111")

      Application.put_env(:ex_aws_configurator, :accounts,
        other: [id: {:system, "OTHER_ACCOUNT_ID"}]
      )

      assert %Account{name: :other, id: "111111111111", region: "us-east-1"} =
               Config.get_account(:other)
    end

    test "raises when the account is not configured" do
      assert_raise ExAwsConfigurator.NoResultsError, ~r/account `unknown`/, fn ->
        Config.get_account(:unknown)
      end
    end

    test "raises when the account has no id" do
      Application.put_env(:ex_aws_configurator, :accounts, %{broken: %{region: "sa-east-1"}})

      assert_raise ArgumentError, ~r/must have an :id/, fn -> Config.get_account(:broken) end
    end
  end

  describe "get_topic/1 with accounts" do
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

      Application.put_env(:ex_aws_configurator, :on_unauthorized, :warn)
      assert %Topic{on_unauthorized: :warn} = Config.get_topic(:t1)
    end

    test "raises on an invalid on_unauthorized" do
      add_topic_to_config(%{t3: %{account: :external, on_unauthorized: :ignore}})

      assert_raise ArgumentError, ~r/invalid :on_unauthorized/, fn -> Config.get_topic(:t3) end
    end
  end

  describe "get_queue/1 with external topics" do
    test "the queue policy allows the external topic arn" do
      add_topic_to_config(%{
        their_topic: %{prefix: "health_api", environment: "test", account: :external}
      })

      add_queue_to_config(%{
        my_queue: %{prefix: "prefix", environment: "test", topics: [:their_topic]}
      })

      queue = Config.get_queue(:my_queue)

      assert %Queue{account: %Account{name: :default}} = queue
      assert Queue.arn(queue) == "arn:aws:sqs:us-east-1:000000000000:prefix_test_my_queue"

      assert %{"Statement" => [%{"Condition" => %{"ArnLike" => %{"aws:SourceArn" => arns}}}]} =
               Jason.decode!(queue.attributes.policy)

      assert arns == ["arn:aws:sns:sa-east-1:#{@external_id}:health_api_test_their_topic"]
    end
  end
end
