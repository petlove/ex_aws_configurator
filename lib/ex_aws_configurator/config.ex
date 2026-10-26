defmodule ExAwsConfigurator.Config do
  @moduledoc """
  The only module that reads the `:ex_aws_configurator` application env.

  It builds `ExAwsConfigurator.Account`, `ExAwsConfigurator.Topic` and
  `ExAwsConfigurator.Queue` structs, either one at a time (`get_account/1`,
  `get_topic/1`, `get_queue/1`) or all at once (`load/0`). The structs it returns are
  complete: every `Topic` and `Queue` carries its `Account`, so computing names, ARNs
  and policies from them never touches the application env again.

  Every scalar read from the env (`account_id`, `region`, `environment`,
  `on_unauthorized` and the `id`/`region` of each account) accepts a
  `{:system, "ENV_VAR"}` tuple, resolved with `System.get_env/1`.
  """

  alias ExAwsConfigurator.{
    Account,
    NoResultsError,
    Propagator,
    Queue,
    QueueAttributes,
    QueueOptions,
    Topic,
    TopicAttributes
  }

  @app :ex_aws_configurator
  @on_unauthorized_modes [:error, :warn]

  @type t :: %__MODULE__{
          accounts: %{atom() => Account.t()},
          topics: %{atom() => Topic.t()},
          queues: %{atom() => Queue.t()}
        }

  defstruct accounts: %{}, topics: %{}, queues: %{}

  @doc """
  Build every account, topic and queue present in the configuration.

  The whole configuration is validated here, before anything touches AWS: an account
  without `id`, an invalid raw `arn`, an unknown `on_unauthorized` mode or a queue
  subscribed to a topic that is not configured all raise.
  """
  @spec load() :: t()
  def load do
    accounts =
      @app
      |> Application.get_env(:accounts, %{})
      |> Map.new(fn {name, _} -> {name, get_account(name)} end)
      |> Map.put(:default, get_account(:default))

    topics = Map.new(topics_env(), fn {name, value} -> {name, build_topic(name, value)} end)

    queues =
      Map.new(queues_env(), fn {name, value} -> {name, build_queue(name, value, topics)} end)

    %__MODULE__{accounts: accounts, topics: topics, queues: queues}
  end

  @doc """
  Fetch an account by name. `:default` is the account built from the global
  `account_id` and `region` keys; any other name must be present under the
  `accounts` key.

  raises `ExAwsConfigurator.NoResultsError` if the account is not configured.
  """
  @spec get_account(atom) :: Account.t()
  def get_account(:default) do
    %Account{name: :default, id: env(:account_id), region: env(:region)}
  end

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
              region: resolve(Map.get(config, :region)) || env(:region)
            }

          _ ->
            raise ArgumentError, "the account `#{name}` must have an :id"
        end

      :error ->
        raise NoResultsError, type: :account, name: name
    end
  end

  @doc """
  The configured `ExAwsConfigurator.Propagator` (`propagator` key): a module, a
  `{module, function, args}` or `nil` when trace context is not propagated.
  """
  @spec propagator() :: Propagator.t()
  def propagator, do: Application.get_env(@app, :propagator)

  @doc "Build the `Topic` struct for the configured topic `name`."
  @spec get_topic(atom) :: Topic.t()
  def get_topic(name) when is_atom(name) do
    case Map.fetch(topics_env(), name) do
      {:ok, value} -> build_topic(name, value)
      :error -> raise NoResultsError, type: :topic, name: name
    end
  end

  @doc "Build the `Queue` struct for the configured queue `name`."
  @spec get_queue(atom) :: Queue.t()
  def get_queue(name) when is_atom(name) do
    case Map.fetch(queues_env(), name) do
      {:ok, value} -> build_queue(name, value, %{})
      :error -> raise NoResultsError, type: :queue, name: name
    end
  end

  defp build_topic(name, value) do
    value = Map.new(value)
    default = get_account(:default)

    {topic, account} =
      case value do
        # A raw ARN bypasses name composition; region and account come from the ARN itself.
        %{arn: arn} when is_binary(arn) ->
          {region, account_id} = parse_arn(arn)

          {%Topic{name: name, arn: arn, region: region},
           %Account{name: :arn, id: account_id, region: region}}

        _ ->
          account = get_account(Map.get(value, :account, :default))

          topic =
            %Topic{name: name, environment: env(:environment), region: account.region}
            |> struct(Map.drop(value, [:account, :attributes, :on_unauthorized]))

          {topic, account}
      end

    %{
      topic
      | account: account,
        external: account.name != :default and account.id != default.id,
        on_unauthorized: on_unauthorized(name, value),
        attributes: struct(%TopicAttributes{}, Map.get(value, :attributes, []))
    }
  end

  # `topics` holds the topics already built by `load/0`; anything missing from it is
  # built on demand, so `get_queue/1` works with an empty map.
  defp build_queue(name, value, topics) do
    value = Map.new(value)
    account = get_account(:default)

    queue_topics =
      value
      |> Map.get(:topics, [])
      |> Enum.map(fn topic_name ->
        Map.get_lazy(topics, topic_name, fn -> get_topic(topic_name) end)
      end)

    queue =
      %Queue{name: name, environment: env(:environment), region: account.region, account: account}
      |> struct(Map.drop(value, [:account, :attributes, :options, :topics]))
      |> struct(%{
        topics: queue_topics,
        options: struct(%QueueOptions{}, Map.get(value, :options, []))
      })

    attributes =
      struct(
        %QueueAttributes{
          policy: Queue.policy(queue),
          redrive_policy: Queue.redrive_policy(queue)
        },
        Map.get(value, :attributes, [])
      )

    %{queue | attributes: attributes}
  end

  defp on_unauthorized(topic_name, value) do
    mode = resolve(Map.get(value, :on_unauthorized, env(:on_unauthorized) || :error))

    if mode in @on_unauthorized_modes do
      mode
    else
      raise ArgumentError,
            "invalid :on_unauthorized `#{inspect(mode)}` for topic `#{topic_name}`, " <>
              "expected one of #{inspect(@on_unauthorized_modes)}"
    end
  end

  defp topics_env, do: Map.new(Application.get_env(@app, :topics, %{}))
  defp queues_env, do: Map.new(Application.get_env(@app, :queues, %{}))

  defp env(key), do: @app |> Application.get_env(key) |> resolve()

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
