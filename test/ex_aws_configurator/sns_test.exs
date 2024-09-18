defmodule ExAwsConfigurator.SNSTest do
  use ExAwsConfigurator.Case

  import ExUnit.CaptureLog

  alias ExAwsConfigurator.SNS

  doctest SNS

  @moduletag capture_log: true

  setup do
    add_topic_to_config(build(:topic_config, name: :topic_name))
    add_topic_to_config(%{topic_min_config: %{}})
    add_topic_to_config(%{:"!nv@l!d-N@me" => %{}})

    SNS.create_topic(:topic_min_config)
    SNS.create_topic(:topic_name)

    add_topic_to_config(build(:topic_config, name: :non_created_topic))
  end

  describe "create_topic/1" do
    test "create topic when receive a atom with correct configuration" do
      assert capture_log(fn ->
               assert {:ok, %{status_code: 200}} = SNS.create_topic(:topic_name)
             end) =~ "created successfully"
    end

    test "create topic with min attributes" do
      assert capture_log(fn ->
               assert {:ok, %{status_code: 200}} = SNS.create_topic(:topic_min_config)
             end) =~ "created successfully"
    end

    test "do not create an invalid topic" do
      assert capture_log(fn ->
               assert {:error, _} = SNS.create_topic(:"!nv@l!d-N@me")
             end) =~ "Error creating topic"
    end

    test "raise when tries to create a topic without configuration" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SNS.create_topic(:not_configured_topic)
      end
    end
  end

  describe "publish/2" do
    test "public an message to an existent topic" do
      SNS.create_topic(:topic_name)

      assert {:ok, %{status_code: 200}} = SNS.publish(:topic_name, "message")
    end

    test "public an message to an non existent topic" do
      assert {:error, {:http_error, 404, _}} = SNS.publish(:non_created_topic, "message")
    end

    test "raise when tries to publish into an no configured topic" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SNS.publish(:not_configured_topic, "message")
      end
    end
  end
end
