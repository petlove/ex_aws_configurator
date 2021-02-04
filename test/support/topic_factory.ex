defmodule ExAwsConfigurator.Factory.Topic do
  @moduledoc false

  alias ExAwsConfigurator.Topic

  defmacro __using__(_opts) do
    quote do
      def topic_factory do
        %Topic{
          name: "queue_name",
          environment: "queue_env",
          region: "queue_region",
          prefix: "queue_prefix"
        }
      end
    end
  end
end
