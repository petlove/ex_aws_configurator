defmodule ExAwsConfigurator.Factory.Config do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      def config_factory do
        %{
          account_id: "000000000000",
          queues: build(:queue_config),
          topics: build(:topic_config)
        }
      end

      def queue_config_factory(attrs) do
        name = Map.get(attrs, :name, :an_queue)

        queue_config =
          %{
            environment: "test",
            prefix: "prefix",
            region: "us-east-1",
            topics: []
          }
          |> merge_attributes(attrs)
          |> Map.delete(:name)

        %{name => queue_config}
      end

      def topic_config_factory(attrs) do
        name = Map.get(attrs, :name, :an_topic)

        topic_config =
          %{
            environment: "test",
            prefix: "prefix",
            region: "us-east-1"
          }
          |> merge_attributes(attrs)
          |> Map.delete(:name)

        %{name => topic_config}
      end
    end
  end
end
