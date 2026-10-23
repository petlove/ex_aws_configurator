defmodule ExAwsConfigurator.Factory.Queue do
  @moduledoc false

  alias ExAwsConfigurator.{Queue, QueueAttributes, QueueOptions}

  defmacro __using__(_opts) do
    quote do
      @doc """
      A complete `%Queue{}` of the default account, with a unique name, ready to be
      handed to the `ExAwsConfigurator.SQS` adapter without touching the application
      env. Pass `topics: [...]` to compute the access policy for them.
      """
      def queue_factory(attrs) do
        topics = Map.get(attrs, :topics, [])

        queue =
          %Queue{
            name: sequence(:queue_name, &:"queue_#{run_id()}_#{&1}"),
            environment: "test",
            region: "us-east-1",
            prefix: "prefix",
            account: build(:default_account),
            attributes: %QueueAttributes{},
            options: %QueueOptions{dead_letter_queue: false},
            topics: topics
          }
          |> merge_attributes(Map.delete(attrs, :topics))

        policy = Queue.policy(queue)

        %{queue | attributes: %{queue.attributes | policy: policy}}
      end

      @doc "A `%Queue{}` whose name carries the `.fifo` suffix and the fifo attributes."
      def fifo_queue_factory(attrs) do
        name = sequence(:fifo_queue_name, &:"queue_#{run_id()}_#{&1}.fifo")

        attrs
        |> Map.put_new(:name, name)
        |> Map.put_new(:attributes, %QueueAttributes{
          fifo_queue: true,
          content_based_deduplication: true
        })
        |> then(&queue_factory/1)
      end
    end
  end
end
