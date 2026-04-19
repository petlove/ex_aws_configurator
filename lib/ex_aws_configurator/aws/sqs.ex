defmodule ExAwsConfigurator.Aws.Sqs do
  @moduledoc """
  Thin behaviour over `ExAws.SQS`. The default implementation calls AWS; tests
  override via `config :ex_aws_configurator, :sqs_impl, MyMock`.
  """

  @type url :: String.t()

  @callback create_queue(name :: String.t(), attrs :: keyword()) ::
              {:ok, url()} | {:error, term()}
  @callback set_queue_attributes(url(), attrs :: keyword()) :: :ok | {:error, term()}
  @callback send_message(url(), message :: String.t(), opts :: keyword()) ::
              {:ok, message_id :: String.t()} | {:error, term()}
  @callback send_message_batch(url(), entries :: [map()]) :: {:ok, map()} | {:error, term()}

  def create_queue(name, attrs), do: impl().create_queue(name, attrs)
  def set_queue_attributes(url, attrs), do: impl().set_queue_attributes(url, attrs)
  def send_message(url, message, opts \\ []), do: impl().send_message(url, message, opts)
  def send_message_batch(url, entries), do: impl().send_message_batch(url, entries)

  defp impl, do: Application.get_env(:ex_aws_configurator, :sqs_impl, __MODULE__.Default)
end

defmodule ExAwsConfigurator.Aws.Sqs.Default do
  @moduledoc false
  @behaviour ExAwsConfigurator.Aws.Sqs

  @impl true
  def create_queue(name, attrs) do
    case ExAws.SQS.create_queue(name, attrs) |> ExAws.request() do
      {:ok, %{body: %{queue_url: url}}} -> {:ok, url}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def set_queue_attributes(url, attrs) do
    case ExAws.SQS.set_queue_attributes(url, attrs) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def send_message(url, message, opts) do
    case ExAws.SQS.send_message(url, message, opts) |> ExAws.request() do
      {:ok, %{body: %{message_id: id}}} -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def send_message_batch(url, entries) do
    case ExAws.SQS.send_message_batch(url, entries) |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end
end
