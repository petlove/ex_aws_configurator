defmodule ExAwsConfigurator.Factory.Topic do
  @moduledoc false

  alias ExAwsConfigurator.Topic

  defmacro __using__(_opts) do
    quote do
      def topic_factory do
        %Topic{
          name: "topic_name",
          environment: "topic_env",
          region: "topic_region",
          prefix: "topic_prefix"
        }
      end
    end
  end
end
