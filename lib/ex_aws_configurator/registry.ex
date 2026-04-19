defmodule ExAwsConfigurator.Registry do
  @moduledoc """
  Runtime lookup of the ARNs, URLs and resolved metadata for every topic and
  queue declared in config.

  The registry is populated once, at boot, by the bootstrapper — it holds the
  full `ExAwsConfigurator.Resolved` tree in `:persistent_term`, so lookups are
  O(1) and lock-free across processes.

  Use these functions when you need direct access to a resource's ARN or URL
  for interop (passing an ARN to a third-party library, building a dashboard,
  wiring up a subscriber that has its own AWS client, etc.). For routine
  publish/send, prefer `ExAwsConfigurator.publish/3` and
  `ExAwsConfigurator.send_to_queue/3` — they use the registry under the hood
  and handle FIFO validation, payload encoding and telemetry.
  """

  alias ExAwsConfigurator.Resolved

  @key {__MODULE__, :resolved}

  @doc false
  @spec put!(Resolved.t()) :: :ok
  def put!(%Resolved{} = resolved) do
    :persistent_term.put(@key, resolved)
  end

  @doc """
  Return the full resolved configuration tree.

  Raises if the registry has not been populated yet (typically because the
  bootstrapper has not run).
  """
  @spec resolved!() :: Resolved.t()
  def resolved! do
    :persistent_term.get(@key)
  rescue
    ArgumentError ->
      raise "ex_aws_configurator: registry not populated — was the bootstrapper run?"
  end

  @doc """
  Return the ARN of a topic by its logical name. Works for both locally-owned
  topics (declared under `:topics`) and external ones (`:external_topics`).
  """
  @spec topic_arn!(atom()) :: String.t()
  def topic_arn!(name) when is_atom(name) do
    resolved = resolved!()

    case Map.get(resolved.topics, name) || Map.get(resolved.external_topics, name) do
      nil -> raise ArgumentError, "unknown topic #{inspect(name)}"
      t -> t.arn
    end
  end

  @doc "Return the URL of a queue by its logical name."
  @spec queue_url!(atom()) :: String.t()
  def queue_url!(name) when is_atom(name), do: queue!(name).url

  @doc "Return the ARN of a queue by its logical name."
  @spec queue_arn!(atom()) :: String.t()
  def queue_arn!(name) when is_atom(name), do: queue!(name).arn

  @doc """
  Return the full resolved queue struct (config, ARN, URL, resolved DLQ,
  resolved topic ARNs). Useful when you need more than a single identifier.
  """
  @spec queue!(atom()) :: Resolved.Queue.t()
  def queue!(name) when is_atom(name) do
    case Map.get(resolved!().queues, name) do
      nil -> raise ArgumentError, "unknown queue #{inspect(name)}"
      q -> q
    end
  end

  @doc false
  @spec reset() :: :ok
  def reset do
    _ = :persistent_term.erase(@key)
    :ok
  end
end
