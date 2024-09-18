defmodule ExAwsConfigurator.NoResultsError do
  defexception [:type, :name, :message]

  def message(%{type: type, name: name}) when not is_nil(type) and not is_nil(name) do
    "the configuration for #{type} `#{name}` is not set"
  end

  def message(%{name: name}) when not is_nil(name) do
    "not found any configuration with key #{name}"
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
end
