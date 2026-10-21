defmodule ExAwsConfigurator.TopicAttributes do
  @type t :: ExAws.SNS.topic_attributes()

  defstruct content_based_deduplication: nil, fifo_topic: nil
end

defmodule ExAwsConfigurator.Topic do
  require Logger

  alias ExAwsConfigurator.{Account, TopicAttributes}

  @type t :: %__MODULE__{
          name: binary(),
          region: binary(),
          environment: binary(),
          prefix: binary(),
          separator: binary(),
          attributes: TopicAttributes,
          account: Account.t(),
          arn: binary() | nil,
          external: boolean(),
          on_unauthorized: :error | :warn
        }

  defstruct name: nil,
            environment: nil,
            region: nil,
            prefix: nil,
            separator: "_",
            attributes: %TopicAttributes{},
            account: %Account{},
            arn: nil,
            external: false,
            on_unauthorized: :error

  @doc """
  get topic arn

  When the topic was configured with a raw `arn`, it is returned as is. Otherwise the
  arn is composed from the topic region, the id of the topic account and `full_name/1`.
  """
  @spec arn(t()) :: String.t()
  def arn(%__MODULE__{arn: arn}) when is_binary(arn), do: arn

  def arn(%__MODULE__{} = topic) do
    ["arn:aws:sns", topic.region, account_id(topic), full_name(topic)]
    |> Enum.join(":")
  end

  @doc "get topic full name, its a composition of `prefix + environment + topic.name`"
  @spec full_name(t()) :: String.t()
  def full_name(%__MODULE__{} = topic) do
    [topic.prefix, topic.environment, topic.name]
    |> Enum.filter(&(!is_nil(&1)))
    |> Enum.join(topic.separator)
  end

  @doc false
  @spec account_id(t()) :: String.t() | nil
  def account_id(%__MODULE__{account: %Account{id: id}}) when is_binary(id), do: id
  def account_id(%__MODULE__{}), do: ExAwsConfigurator.get_env(:account_id)
end
