defmodule ExAwsConfigurator.SNSTest do
  use ExAwsConfigurator.Case, async: true

  import ExUnit.CaptureLog

  alias ExAwsConfigurator.{HttpStub, SNS, Topic}

  doctest SNS

  @moduletag capture_log: true

  describe "create_topic/1 with a struct" do
    test "creates the topic" do
      topic = build(:topic)

      assert capture_log(fn ->
               assert {:ok, %{status_code: 200}} = SNS.create_topic(topic)
             end) =~ "Topic #{Topic.full_name(topic)} created successfully"
    end

    test "creates a topic with min attributes" do
      topic = build(:topic, prefix: nil, environment: nil)

      assert capture_log(fn ->
               assert {:ok, %{status_code: 200}} = SNS.create_topic(topic)
             end) =~ ~r/(created|updated) successfully/
    end

    test "creates a fifo topic" do
      topic = build(:fifo_topic)

      assert {:ok, %{status_code: 200}} = SNS.create_topic(topic)
      assert Topic.full_name(topic) =~ ~r/\.fifo$/
    end

    test "updates the topic when it already exists" do
      topic = build(:topic)

      assert {:ok, %{status_code: 200}} = SNS.create_topic(topic)

      assert capture_log(fn ->
               assert {:ok, %{status_code: 200}} = SNS.create_topic(topic)
             end) =~ "already exists on us-east-1, updating attributes"
    end

    test "updates the mutable attributes of an existing fifo topic" do
      topic = build(:fifo_topic)

      assert {:ok, %{status_code: 200}} = SNS.create_topic(topic)

      assert capture_log(fn ->
               assert {:ok, %{status_code: 200}} = SNS.create_topic(topic)
             end) =~ "Topic #{Topic.full_name(topic)} updated successfully"
    end

    test "returns the error when the attributes cannot be updated" do
      topic = build(:fifo_topic)

      assert {:ok, %{status_code: 200}} = SNS.create_topic(topic)
      HttpStub.fail("SetTopicAttributes")

      assert capture_log(fn ->
               assert {:error, {:http_error, 403, %{code: "AccessDenied"}}} =
                        SNS.create_topic(topic)
             end) =~ "Error updating topic #{Topic.full_name(topic)}"
    end

    test "returns the error when the topic cannot be fetched" do
      topic = build(:topic)
      HttpStub.fail("GetTopicAttributes")

      assert capture_log(fn ->
               assert {:error, {:http_error, 403, %{code: "AccessDenied"}}} =
                        SNS.create_topic(topic)
             end) =~ "Error fetching topic #{Topic.full_name(topic)}"
    end

    test "does not create an external topic" do
      topic = build(:external_topic)

      assert capture_log(fn ->
               assert {:ok, :external} = SNS.create_topic(topic)
             end) =~ "Skipping topic #{Topic.arn(topic)}"
    end

    test "does not create an invalid topic" do
      topic = build(:topic, name: :"!nv@l!d-N@me")

      assert capture_log(fn ->
               assert {:error, _} = SNS.create_topic(topic)
             end) =~ "Error creating topic"
    end
  end

  describe "create_topic/1 with an atom" do
    test "fetches the topic from the configuration and creates it" do
      assert {:ok, %{status_code: 200}} = SNS.create_topic(:an_topic)
    end

    test "raises when the topic is not configured" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SNS.create_topic(:not_configured_topic)
      end
    end
  end

  describe "publish/3" do
    setup do
      topic = build(:topic)
      {:ok, _} = SNS.create_topic(topic)

      %{topic: topic}
    end

    test "publishes a message to an existent topic", %{topic: topic} do
      assert {:ok, %{status_code: 200}} = SNS.publish(topic, "message")
    end

    test "encodes maps as json and forwards opts to ExAws", %{topic: topic} do
      attributes = [%{name: "traceparent", data_type: :string, value: {:string, "00-abc-def-01"}}]

      assert {:ok, %{status_code: 200}} =
               SNS.publish(topic, %{event: "created"}, message_attributes: attributes)
    end

    test "returns the error for a non existent topic" do
      assert {:error, {:http_error, 404, _}} = SNS.publish(build(:topic), "message")
    end

    test "accepts the configured topic name" do
      {:ok, _} = SNS.create_topic(:an_topic)

      assert {:ok, %{status_code: 200}} = SNS.publish(:an_topic, "message")
    end

    test "raises when the topic is not configured" do
      assert_raise ExAwsConfigurator.NoResultsError, fn ->
        SNS.publish(:not_configured_topic, "message")
      end
    end
  end
end
