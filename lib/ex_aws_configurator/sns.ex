defmodule ExAwsConfigurator.SNS do
  @moduledoc """
  SNS adapter: creates and updates topics and publishes messages.

  Every function accepts either a `ExAwsConfigurator.Topic` struct or the atom that
  names the topic in the configuration. The atom form fetches the struct with
  `ExAwsConfigurator.get_topic/1` and delegates to the struct form.
  """

  require Logger

  alias ExAws.SNS
  alias ExAwsConfigurator.Topic

  @fifo_attributes [:content_based_deduplication, :fifo_topic]
  # Attributes that AWS allows changing after the topic exists.
  @mutable_attributes [:content_based_deduplication]

  @doc """
  Create an sns topic, or update its mutable attributes when it already exists.

  Topics that belong to an external account (see `ExAwsConfigurator.Account`) are never
  created: they are managed by their owner, so this function only logs and returns
  `{:ok, :external}`.

  raises `ExAwsConfigurator.NoResultsError` if the atom form is used and no
  configuration was found.

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

      ExAwsConfigurator.SNS.create_topic(:an_topic)
      #=> {:ok, term()}

  will create a topic named `prefix + environment + map_key`, the result will be _topic_prefix_environment_an_topic_ on region _us-east-1_

  the response term() will be the `ExAws` response without any modification

      ExAwsConfigurator.SNS.create_topic(:not_exist)
      #=> ** (ExAwsConfigurator.NoResultsError) the configuration for topic not_exist is not set
  """
  @spec create_topic(Topic.t() | atom) :: {:ok, term} | {:error, term}
  def create_topic(%Topic{external: true} = topic) do
    Logger.info(
      "Skipping topic #{Topic.arn(topic)}: it belongs to the external account " <>
        "#{inspect(topic.account.name)} and is managed by its owner"
    )

    {:ok, :external}
  end

  def create_topic(%Topic{} = topic), do: create_or_update_topic(topic)

  def create_topic(topic_name) when is_atom(topic_name),
    do: topic_name |> ExAwsConfigurator.get_topic() |> create_topic()

  @doc """
  Publish a message to a topic.

  Maps and lists are JSON encoded, binaries are sent as they are. `opts` are passed to
  `ExAws.SNS.publish/2` (for example `message_attributes`, `message_group_id`).
  """
  @spec publish(Topic.t() | atom, map | list | binary, keyword) :: {:ok, term} | {:error, term}
  def publish(topic, message, opts \\ [])

  def publish(%Topic{} = topic, message, opts) do
    Logger.info("Publish message to #{Topic.full_name(topic)}")

    message
    |> encode()
    |> SNS.publish(Keyword.put(opts, :topic_arn, Topic.arn(topic)))
    |> ExAws.request(region: topic.region)
  end

  def publish(topic_name, message, opts) when is_atom(topic_name),
    do: topic_name |> ExAwsConfigurator.get_topic() |> publish(message, opts)

  defp create_or_update_topic(topic) do
    full_name = Topic.full_name(topic)
    arn = Topic.arn(topic)

    case arn |> SNS.get_topic_attributes() |> ExAws.request(region: topic.region) do
      {:ok, _} = response ->
        update_topic(topic, full_name, arn, response)

      {:error, {:http_error, 404, _}} ->
        create_topic_on_sns(topic, full_name)

      {:error, term} = error ->
        Logger.error(
          "Error fetching topic #{full_name} on #{topic.region}, reason: #{inspect(term)}"
        )

        error
    end
  end

  defp create_topic_on_sns(topic, full_name) do
    attributes =
      topic.attributes
      |> Map.from_struct()
      |> Enum.reject(fn {key, value} -> key in @fifo_attributes and is_nil(value) end)

    Logger.info("Creating topic #{full_name} on #{topic.region}")

    result =
      full_name
      |> SNS.create_topic(attributes)
      |> ExAws.request(region: topic.region)

    case result do
      {:ok, _} ->
        Logger.info("Topic #{full_name} created successfully on #{topic.region}")

      {:error, term} ->
        Logger.error(
          "Error creating topic #{full_name} on #{topic.region}, reason: #{inspect(term)}"
        )
    end

    result
  end

  defp update_topic(topic, full_name, arn, current_response) do
    Logger.info("Topic #{full_name} already exists on #{topic.region}, updating attributes")

    attributes =
      topic.attributes
      |> Map.from_struct()
      |> Enum.filter(fn {key, value} -> key in @mutable_attributes and not is_nil(value) end)

    result =
      Enum.reduce_while(attributes, current_response, fn {key, value}, _acc ->
        case key
             |> SNS.set_topic_attributes(to_string(value), arn)
             |> ExAws.request(region: topic.region) do
          {:ok, _} = ok -> {:cont, ok}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, _} ->
        Logger.info("Topic #{full_name} updated successfully on #{topic.region}")

      {:error, term} ->
        Logger.error(
          "Error updating topic #{full_name} on #{topic.region}, reason: #{inspect(term)}"
        )
    end

    result
  end

  defp encode(message) when is_binary(message), do: message
  defp encode(message), do: Jason.encode!(message)
end
