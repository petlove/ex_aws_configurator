defmodule ExAwsConfigurator.Bootstrapper do
  @moduledoc false

  require Logger

  alias ExAwsConfigurator.{Config, Registry, Resolved, Resolver}
  alias ExAwsConfigurator.Aws.Identity
  alias ExAwsConfigurator.Ensure

  @max_concurrency 10

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :transient
    }
  end

  @spec start_link() :: :ignore
  def start_link do
    run!()
    :ignore
  end

  @spec run!() :: Resolved.t()
  def run! do
    Logger.info("[ex_aws_configurator] starting bootstrap")

    config = Config.load!()
    identity = Identity.fetch!()
    resolved = Resolver.resolve(config, identity)
    Registry.put!(resolved)

    ensure_topics!(resolved)
    ensure_dlqs!(resolved)
    ensure_queues!(resolved)
    ensure_subscriptions!(resolved)

    Logger.info("[ex_aws_configurator] bootstrap completed")
    resolved
  end

  defp ensure_topics!(%Resolved{topics: topics}) do
    topics
    |> Map.values()
    |> parallel_run("topic", &Ensure.Topic.run/1)
  end

  defp ensure_dlqs!(%Resolved{queues: queues}) do
    queues
    |> Map.values()
    |> Enum.filter(& &1.dlq)
    |> parallel_run("dlq", fn q -> Ensure.Dlq.run(q.dlq, q.config.fifo) end)
  end

  defp ensure_queues!(%Resolved{queues: queues}) do
    queues
    |> Map.values()
    |> parallel_run("queue", &Ensure.Queue.run/1)
  end

  defp ensure_subscriptions!(%Resolved{queues: queues}) do
    queues
    |> Map.values()
    |> Enum.reject(&(&1.subscribe_to_arns == []))
    |> parallel_run("subscription", &Ensure.Subscription.run/1)
  end

  defp parallel_run(phase, items, fun) do
    items
    |> Task.async_stream(fun, max_concurrency: @max_concurrency, ordered: false, timeout: 30_000)
    |> Enum.each(fn
      {:ok, _} ->
        :ok

      {:exit, reason} ->
        raise "ex_aws_configurator: #{phase} ensure task failed: #{inspect(reason)}"
    end)
  end
end
