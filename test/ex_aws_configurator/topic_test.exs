defmodule ExAwsConfigurator.TopicTest do
  use ExAwsConfigurator.Case

  alias ExAwsConfigurator.{Topic, TopicAttributes}

  doctest Topic

  setup do
    topic =
      build(:topic, %{
        region: "reg",
        prefix: "pref",
        environment: "env",
        name: "topic"
      })

    {:ok, %{topic: topic}}
  end

  describe "arn/1" do
    test "build arn from topic", %{topic: topic} do
      assert "arn:aws:sns:reg:000000000000:pref_env_topic" = Topic.arn(topic)
    end
  end

  describe "full_name/1" do
    test "build full_name from topic", %{topic: topic} do
      assert "pref_env_topic" = Topic.full_name(topic)
    end

    test "uses custom separator when configured", %{topic: topic} do
      topic = %{topic | separator: "-"}
      assert "pref-env-topic" = Topic.full_name(topic)
    end
  end

  describe "default attributes" do
    test "TopicAttributes defaults" do
      assert struct(TopicAttributes) == %TopicAttributes{
               content_based_deduplication: nil,
               fifo_topic: nil
             }
    end
  end
end
