defmodule ExAwsConfigurator.Config do
  @moduledoc """
  Builds `ExAwsConfigurator.Account`, `ExAwsConfigurator.Topic` and
  `ExAwsConfigurator.Queue` structs from the `:ex_aws_configurator` application env.
  """

  alias ExAwsConfigurator.{
    Account,
    NoResultsError,
    Queue,
    QueueAttributes,
    QueueOptions,
    Topic,
    TopicAttributes
  }

  @app :ex_aws_configurator
  @on_unauthorized_modes [:error, :warn]

  @doc "The account built from the global `account_id` and `region` keys."
  @spec default_account() :: Account.t()
  def default_account do
    %Account{
      name: :default,
      id: ExAwsConfigurator.get_env(:account_id),
      region: Application.get_env(@app, :region)
    }
  end

  @doc """
  Fetch an account by name. `:default` returns `default_account/0`; any other name
  must be present under the `accounts` key.

  raises `ExAwsConfigurator.NoResultsError` if the account is not configured.
  """
  @spec get_account(atom) :: Account.t()
  def get_account(:default), do: default_account()

  def get_account(name) when is_atom(name) do
    accounts = Application.get_env(@app, :accounts, %{})

    case Map.fetch(Map.new(accounts), name) do
      {:ok, config} ->
        config = Map.new(config)

        case resolve(Map.get(config, :id)) do
          id when is_binary(id) ->
            %Account{
              name: name,
              id: id,
              region: resolve(Map.get(config, :region)) || Application.get_env(@app, :region)
            }

          _ ->
            raise ArgumentError, "the account `#{name}` must have an :id"
        end

      :error ->
        raise NoResultsError, type: :account, name: name
    end
  end

  @doc "Build the `Topic` struct for the configured topic `name`."
  @spec get_topic(atom) :: Topic.t()
  def get_topic(name) when is_atom(name) do
    case Map.fetch(ExAwsConfigurator.get_env(:topics), name) do
      {:ok, value} -> build_topic(name, Map.new(value))
      :error -> raise NoResultsError, type: :topic, name: name
    end
  end

  @doc "Build the `Queue` struct for the configured queue `name`."
  @spec get_queue(atom) :: Queue.t()
  def get_queue(name) when is_atom(name) do
    case Map.fetch(ExAwsConfigurator.get_env(:queues), name) do
      {:ok, value} -> build_queue(name, Map.new(value))
      :error -> raise NoResultsError, type: :queue, name: name
    end
  end

  # A raw ARN bypasses name composition; region and account come from the ARN itself.
  defp build_topic(name, %{arn: arn} = value) when is_binary(arn) do
    {region, account_id} = parse_arn(arn)
    account = %Account{name: :arn, id: account_id, region: region}

    %Topic{name: name, arn: arn, region: region}
    |> put_account(account)
    |> put_on_unauthorized(value)
    |> put_topic_attributes(value)
  end

  defp build_topic(name, value) do
    account = get_account(Map.get(value, :account, :default))

    %Topic{name: name, environment: environment(), region: account.region}
    |> put_account(account)
    |> struct(Map.drop(value, [:account, :attributes, :on_unauthorized]))
    |> put_on_unauthorized(value)
    |> put_topic_attributes(value)
  end

  defp build_queue(name, value) do
    account = default_account()
    topics = value |> Map.get(:topics, []) |> Enum.map(&get_topic/1)

    queue =
      %Queue{name: name, environment: environment(), region: account.region, account: account}
      |> struct(Map.drop(value, [:account, :attributes, :options, :topics]))
      |> struct(%{
        topics: topics,
        options: struct(%QueueOptions{}, Map.get(value, :options, []))
      })

    attributes =
      struct(%QueueAttributes{policy: Queue.policy(queue)}, Map.get(value, :attributes, []))

    %{queue | attributes: attributes}
  end

  defp put_account(%Topic{} = topic, %Account{} = account) do
    default = default_account()
    %{topic | account: account, external: account.name != :default and account.id != default.id}
  end

  defp put_on_unauthorized(%Topic{} = topic, value) do
    mode = Map.get(value, :on_unauthorized, Application.get_env(@app, :on_unauthorized, :error))

    if mode in @on_unauthorized_modes do
      %{topic | on_unauthorized: mode}
    else
      raise ArgumentError,
            "invalid :on_unauthorized `#{inspect(mode)}` for topic `#{topic.name}`, " <>
              "expected one of #{inspect(@on_unauthorized_modes)}"
    end
  end

  defp put_topic_attributes(%Topic{} = topic, value) do
    %{topic | attributes: struct(%TopicAttributes{}, Map.get(value, :attributes, []))}
  end

  defp environment, do: Application.get_env(@app, :environment)

  defp resolve({:system, var}) when is_binary(var), do: System.get_env(var)
  defp resolve(value), do: value

  # arn:aws:sns:<region>:<account_id>:<name>
  defp parse_arn(arn) do
    case String.split(arn, ":", parts: 6) do
      ["arn", _partition, "sns", region, account_id, _name] -> {region, account_id}
      _ -> raise ArgumentError, "invalid SNS topic arn `#{arn}`"
    end
  end
end
