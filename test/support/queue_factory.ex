defmodule ExAwsConfigurator.Factory.Queue do
  @moduledoc false

  alias ExAwsConfigurator.Queue

  defmacro __using__(_opts) do
    quote do
      def queue_factory do
        %Queue{
          name: "queue_name",
          environment: "queue_env",
          region: "queue_region",
          prefix: "queue_prefix",
          attributes: [
            fifo_queue: false,
            content_based_deduplication: false,
            max_receive_count: 7,
            dead_letter_queue: false,
            dead_letter_queue_suffix: "_failures",
            visibility_timeout: 60,
            message_retention_period: 1_209_600
          ],
          topics: []
        }
      end
    end
  end
end
