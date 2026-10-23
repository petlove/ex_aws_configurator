defmodule ExAwsConfigurator.NoResultsError do
  defexception [:type, :name, :message]

  def message(%{type: type, name: name}) do
    "the configuration for #{type} `#{name}` is not set"
  end
end

defmodule ExAwsConfigurator.SetupError do
  defexception [:type, :message]

  def message(%{type: :topics}),
    do:
      "something went wrong when creating the topics, ensure that the credentials have the necessary permissions to perform this operation"

  def message(%{type: :queues}),
    do:
      "something went wrong when creating the queues, ensure that the credentials have the necessary permissions to perform this operation in addition to being able to subscribe to topics"

  def message(%{type: :subscriptions}),
    do:
      "something went wrong when subscribing the queues to the topics, ensure that the credentials have the necessary permissions and, for external topics, that the topic owner allows sns:Subscribe from this account (or set `on_unauthorized: :warn` on the topic)"
end
