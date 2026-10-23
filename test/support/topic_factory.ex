defmodule ExAwsConfigurator.Factory.Topic do
  @moduledoc false

  alias ExAwsConfigurator.{Account, HttpStub, Topic, TopicAttributes}

  defmacro __using__(_opts) do
    quote do
      @doc "The account built from the test config (`account_id` and `region`)."
      def default_account_factory do
        %Account{name: :default, id: "000000000000", region: "us-east-1"}
      end

      @doc "The account that refuses `sns:Subscribe` in `ExAwsConfigurator.HttpStub`."
      def external_account_factory do
        %Account{name: :external, id: HttpStub.external_account_id(), region: "sa-east-1"}
      end

      @doc """
      A complete `%Topic{}` of the default account, with a unique name, ready to be
      handed to the `ExAwsConfigurator.SNS` adapter without touching the application env.
      """
      def topic_factory do
        %Topic{
          name: sequence(:topic_name, &:"topic_#{run_id()}_#{&1}"),
          environment: "test",
          region: "us-east-1",
          prefix: "prefix",
          account: build(:default_account)
        }
      end

      @doc "A `%Topic{}` whose name carries the `.fifo` suffix and the fifo attributes."
      def fifo_topic_factory do
        %Topic{
          build(:topic)
          | name: sequence(:fifo_topic_name, &:"topic_#{run_id()}_#{&1}.fifo"),
            attributes: %TopicAttributes{fifo_topic: true, content_based_deduplication: true}
        }
      end

      @doc "A `%Topic{}` owned by the external account: never created, subscribe is refused."
      def external_topic_factory do
        account = build(:external_account)

        %Topic{
          name: sequence(:external_topic_name, &:"their_topic_#{run_id()}_#{&1}"),
          environment: "test",
          region: account.region,
          prefix: "theirs",
          account: account,
          external: true
        }
      end
    end
  end
end
