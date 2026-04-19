defmodule ExAwsConfigurator.Aws.Sns do
  @moduledoc """
  Thin behaviour over `ExAws.SNS`. The default implementation calls AWS; tests
  override via `config :ex_aws_configurator, :sns_impl, MyMock`.

  Every callback normalizes ExAws's nested `%{body: ...}` result into a direct
  `{:ok, value}` — callers should not have to pattern-match on ExAws shapes.
  """

  @type arn :: String.t()

  @callback create_topic(name :: String.t(), attrs :: keyword()) ::
              {:ok, arn()} | {:error, term()}
  @callback list_subscriptions_by_topic(arn()) :: {:ok, [map()]} | {:error, term()}
  @callback subscribe(topic_arn :: arn(), queue_arn :: arn(), attributes :: map()) ::
              {:ok, arn()} | {:error, term()}
  @callback set_subscription_attribute(arn(), key :: String.t(), value :: term()) ::
              :ok | {:error, term()}
  @callback publish(arn(), message :: String.t(), opts :: keyword()) ::
              {:ok, message_id :: String.t()} | {:error, term()}
  @callback publish_batch(arn(), entries :: [map()]) :: {:ok, map()} | {:error, term()}

  def create_topic(name, attrs), do: impl().create_topic(name, attrs)
  def list_subscriptions_by_topic(arn), do: impl().list_subscriptions_by_topic(arn)
  def subscribe(topic, queue, attrs \\ %{}), do: impl().subscribe(topic, queue, attrs)

  def set_subscription_attribute(arn, key, value),
    do: impl().set_subscription_attribute(arn, key, value)

  def publish(arn, message, opts \\ []), do: impl().publish(arn, message, opts)
  def publish_batch(arn, entries), do: impl().publish_batch(arn, entries)

  defp impl, do: Application.get_env(:ex_aws_configurator, :sns_impl, __MODULE__.Default)
end

defmodule ExAwsConfigurator.Aws.Sns.Default do
  @moduledoc false
  @behaviour ExAwsConfigurator.Aws.Sns

  @impl true
  def create_topic(name, attrs) do
    case ExAws.SNS.create_topic(name, attrs) |> ExAws.request() do
      {:ok, %{body: %{topic_arn: arn}}} -> {:ok, arn}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list_subscriptions_by_topic(topic_arn) do
    case ExAws.SNS.list_subscriptions_by_topic(topic_arn) |> ExAws.request() do
      {:ok, %{body: %{subscriptions: subs}}} -> {:ok, subs}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def subscribe(topic_arn, queue_arn, _attributes) do
    case ExAws.SNS.subscribe(topic_arn, "sqs", queue_arn) |> ExAws.request() do
      {:ok, %{body: %{subscription_arn: arn}}} -> {:ok, arn}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def set_subscription_attribute(subscription_arn, key, value) do
    case ExAws.SNS.set_subscription_attributes(key, value, subscription_arn) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def publish(topic_arn, message, opts) do
    params = Keyword.put(opts, :topic_arn, topic_arn)

    case ExAws.SNS.publish(message, params) |> ExAws.request() do
      {:ok, %{body: %{message_id: id}}} -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def publish_batch(topic_arn, entries) do
    case ExAws.SNS.publish_batch(topic_arn, entries) |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end
end
