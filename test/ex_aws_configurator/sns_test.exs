defmodule ExAwsConfigurator.SNSTest do
  use ExAwsConfigurator.Case, async: true

  alias ExAwsConfigurator.SNS

  doctest SNS

  @moduletag capture_log: true

  describe "create_topic/1" do
    test "create topic when receive a atom with correct configuration" do
      add_topic_to_config(build(:topic_config, name: :topic_name))

      assert {:ok, %{status_code: 200}} = SNS.create_topic(:topic_name)
    end

    test "create topic when receive a Topic with correct configuration" do
      add_topic_to_config(build(:topic_config, name: :topic_name))

      topic = ExAwsConfigurator.get_topic(:topic_name)

      assert {:ok, %{status_code: 200}} = SNS.create_topic(topic)
    end

    test "raise when tries to create a topic without configuration" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SNS.create_topic(:not_configured_topic)
      end
    end
  end

  describe "publish/2" do
    test "public an message to an existent topic" do
      add_topic_to_config(build(:topic_config, name: :topic_name))

      SNS.create_topic(:topic_name)

      assert {:ok, %{status_code: 200}} = SNS.publish(:topic_name, "message")
    end

    test "public an message to an non existent topic" do
      add_topic_to_config(build(:topic_config, name: :non_created))

      assert {:error, {:http_error, 404, _}} = SNS.publish(:non_created, "message")
    end

    test "raise when tries to publish into an no configured topic" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SNS.publish(:not_configured_topic, "message")
      end
    end
  end
end
