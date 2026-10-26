defmodule ExAwsConfigurator.Telemetry do
  @moduledoc """
  `:telemetry` events emitted by the configurator and ready-made `Telemetry.Metrics`
  definitions for them.

  Every call that touches AWS is wrapped in `:telemetry.span/3`, so each one emits a
  `:start`, a `:stop` and, when it raises, an `:exception` event under
  `[:ex_aws_configurator, operation]`:

  | operation | emitted by | metadata |
  |-----------|------------|----------|
  | `:publish` | `ExAwsConfigurator.SNS.publish/3` | `topic`, `topic_arn`, `region`, `account` |
  | `:send_message` | `ExAwsConfigurator.SQS.send_message/3` | `queue`, `queue_arn`, `region`, `account` |
  | `:create_topic` | `ExAwsConfigurator.SNS.create_topic/1` | `topic`, `topic_arn`, `region`, `account` |
  | `:create_queue` | `ExAwsConfigurator.SQS.create_queue/2` | `queue`, `queue_arn`, `region`, `account` |
  | `:subscribe` | `ExAwsConfigurator.SQS.subscribe/2` | `queue`, `topic`, `queue_arn`, `topic_arn`, `region` |
  | `:setup` | `ExAwsConfigurator.setup/0` | – |

  `topic` and `queue` are the atoms that name the resource in the configuration (the
  struct `name`); `account` is the account name (`:default` or one declared under
  `accounts`). A queue with a dead letter queue emits one `:create_queue` span for each.

  The `:stop` event adds `result` (`:ok` or `:error`) and, on error, `error` with the
  reason returned by the call (for `:setup`, the phase that failed: `:topics`, `:queues`
  or `:subscriptions`). Measurements are the ones of `:telemetry.span/3`: `system_time`
  on `:start`, `duration` (native time unit) on `:stop` and `:exception`.

  ## Metrics

  `metrics/1` returns `Telemetry.Metrics` definitions for these events (it needs the
  `telemetry_metrics` package in your deps). Add them to the reporter your app already
  runs, for example `TelemetryMetricsStatsd` sending to the Datadog agent:

      # lib/my_app_web/telemetry.ex
      def metrics do
        [
          counter("my_app.api.request.count"),
          # ...
        ] ++ ExAwsConfigurator.Telemetry.metrics("my_app")
      end

  With the prefix `"my_app"` the metrics are:

    * `my_app.sns.publish.count`, `my_app.sns.publish.duration` (milliseconds) and
      `my_app.sns.publish.exception.count`, tagged by `topic` and `result`
      (`kind` for the exception count);
    * `my_app.sqs.send_message.count`, `my_app.sqs.send_message.duration` and
      `my_app.sqs.send_message.exception.count`, tagged by `queue` and `result`;
    * `my_app.setup.count` and `my_app.setup.duration`, tagged by `result`.
  """

  alias ExAwsConfigurator.{Queue, Topic}

  @prefix :ex_aws_configurator

  @doc false
  @spec span(atom, map, (-> result)) :: result when result: term
  def span(operation, metadata, fun) do
    :telemetry.span([@prefix, operation], metadata, fn ->
      result = fun.()
      {result, Map.merge(metadata, result_metadata(result))}
    end)
  end

  @doc false
  @spec metadata(Topic.t() | Queue.t()) :: map
  def metadata(%Topic{} = topic) do
    %{
      topic: topic.name,
      topic_arn: Topic.arn(topic),
      region: topic.region,
      account: topic.account.name
    }
  end

  def metadata(%Queue{} = queue) do
    %{
      queue: queue.name,
      queue_arn: Queue.arn(queue),
      region: queue.region,
      account: queue.account.name
    }
  end

  @doc false
  @spec metadata(Queue.t(), Topic.t()) :: map
  def metadata(%Queue{} = queue, %Topic{} = topic) do
    %{
      queue: queue.name,
      topic: topic.name,
      queue_arn: Queue.arn(queue),
      topic_arn: Topic.arn(topic),
      region: topic.region
    }
  end

  defp result_metadata(:ok), do: %{result: :ok}
  defp result_metadata({:ok, _}), do: %{result: :ok}
  defp result_metadata({:error, reason}), do: %{result: :error, error: reason}

  # Remote calls only: an `import` would be resolved at expansion time and break the
  # compilation of apps that do not have `telemetry_metrics`.
  if Code.ensure_loaded?(Telemetry.Metrics) do
    @doc """
    `Telemetry.Metrics` definitions for the events above, named under `prefix` (see the
    module docs for the list).
    """
    @spec metrics(String.t() | atom) :: [Telemetry.Metrics.t()]
    def metrics(prefix) when is_binary(prefix) or is_atom(prefix) do
      operation_metrics("#{prefix}.sns.publish", :publish, :topic) ++
        operation_metrics("#{prefix}.sqs.send_message", :send_message, :queue) ++
        [
          Telemetry.Metrics.counter("#{prefix}.setup.count",
            event_name: [@prefix, :setup, :stop],
            tags: [:result]
          ),
          Telemetry.Metrics.distribution("#{prefix}.setup.duration",
            event_name: [@prefix, :setup, :stop],
            measurement: :duration,
            unit: {:native, :millisecond},
            tags: [:result]
          )
        ]
    end

    defp operation_metrics(name, operation, resource) do
      stop = [@prefix, operation, :stop]

      [
        Telemetry.Metrics.counter("#{name}.count", event_name: stop, tags: [resource, :result]),
        Telemetry.Metrics.distribution("#{name}.duration",
          event_name: stop,
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [resource, :result]
        ),
        Telemetry.Metrics.counter("#{name}.exception.count",
          event_name: [@prefix, operation, :exception],
          tags: [resource, :kind]
        )
      ]
    end
  else
    @doc """
    `Telemetry.Metrics` definitions for the events above, named under `prefix`. Needs the
    `telemetry_metrics` package in your deps.
    """
    @spec metrics(String.t() | atom) :: no_return
    def metrics(_prefix) do
      raise ArgumentError,
            "ExAwsConfigurator.Telemetry.metrics/1 needs the :telemetry_metrics package, " <>
              "add {:telemetry_metrics, \"~> 1.0\"} to your deps"
    end
  end
end
