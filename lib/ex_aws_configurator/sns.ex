defmodule ExAwsConfigurator.SNS do
  require Logger

  alias ExAws.SNS
  alias ExAwsConfigurator.Topic

  @doc """
  Create an sns topic, based on ex_aws_configurator configuration

  raises `ExAwsConfigurator.NoResultsError` if no configuration was found.

  for the example below, we will consider the following settings

      # config/config.exs

      config :ex_aws_configurator,
        ...
        topics: %{
          an_topic: %{
            region: "us-east-1",
            prefix: "topic_prefix",
            environment: "environment"
          }
        }

  ## Examples

      ExAwsConfigurator.create_topic(:an_topic)
      #=> {:ok, term()}

  will create a topic named `prefix + environment + map_key`, the result will be _topic_prefix_environment_an_topic_ on region _us-east-1_

  the response term() will be the `ExAws` response without any modification

      ExAwsConfigurator.get_queue(:not_exist)
      #=> ** (ExAwsConfigurator.NoResultsError) the configuration for queue not_exist is not set
  """
  @spec create_topic(atom) :: {:ok, term} | {:error, term}
  def create_topic(topic_name) when is_atom(topic_name) do
    topic_name
    |> ExAwsConfigurator.get_topic()
    |> create_topic()
  end

  @spec create_topic(Topic.t()) :: {:ok, term} | {:error, term}
  def create_topic(%Topic{} = topic) do
    full_name = Topic.full_name(topic)
    region = Topic.region(topic)

    Logger.info("Creating topic #{full_name} on #{region}")

    full_name
    |> SNS.create_topic()
    |> ExAws.request(region: region)
  end

  @doc """
    Publish an message to a topic based on clan configuration
  """
  @spec publish(atom, atom) :: {:ok, term} | {:error, term}
  def publish(topic_name, message) when is_atom(topic_name) do
    topic_name
    |> ExAwsConfigurator.get_topic()
    |> publish(message)
  end

  @spec publish(Topic.t(), atom) :: {:ok, term} | {:error, term}
  def publish(%Topic{} = topic, message) do
    Logger.info("Publish message to #{Topic.full_name(topic)}")

    message
    |> Jason.encode!()
    |> SNS.publish(topic_arn: Topic.arn(topic))
    |> ExAws.request(region: Topic.region(topic))
  end
end
