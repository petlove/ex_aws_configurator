defmodule ExAwsConfigurator.Resolver do
  @moduledoc false

  alias ExAwsConfigurator.Config
  alias ExAwsConfigurator.Config.{ExternalTopic, Queue, Topic}

  alias ExAwsConfigurator.Resolved
  alias ExAwsConfigurator.Resolved.{Dlq, ExternalTopic, Queue, Topic}

  @spec resolve(Config.t(), %{account_id: String.t(), region: String.t()}) :: Resolved.t()
  def resolve(%Config{} = config, %{account_id: _, region: _} = identity) do
    topics =
      config.topics
      |> Enum.map(&{&1.name, resolve_topic(&1, config.queue_prefix, identity)})
      |> Map.new()

    external_topics =
      config.external_topics
      |> Enum.map(&{&1.name, resolve_external_topic(&1, identity)})
      |> Map.new()

    arn_by_topic_name =
      topics
      |> Enum.map(fn {name, t} -> {name, t.arn} end)
      |> Enum.concat(Enum.map(external_topics, fn {name, t} -> {name, t.arn} end))
      |> Map.new()

    queues =
      config.queues
      |> Enum.map(
        &{&1.name, resolve_queue(&1, config.queue_prefix, identity, arn_by_topic_name)}
      )
      |> Map.new()

    %Resolved{
      identity: identity,
      topics: topics,
      external_topics: external_topics,
      queues: queues
    }
  end

  defp resolve_topic(%Config.Topic{} = topic, prefix, identity) do
    full_name = full_name(prefix, topic.name, topic.fifo)

    %Topic{
      config: topic,
      full_name: full_name,
      arn: sns_arn(identity.region, identity.account_id, full_name)
    }
  end

  defp resolve_external_topic(%Config.ExternalTopic{arn: arn} = ext, _identity) when is_binary(arn) do
    %ExternalTopic{config: ext, full_name: nil, arn: arn}
  end

  defp resolve_external_topic(%Config.ExternalTopic{prefix: prefix} = ext, identity)
       when is_binary(prefix) do
    region = ext.region || identity.region
    account_id = ext.account_id || identity.account_id
    full_name = "#{prefix}_#{ext.name}" |> maybe_fifo(ext.fifo)

    %ExternalTopic{
      config: ext,
      full_name: full_name,
      arn: sns_arn(region, account_id, full_name)
    }
  end

  defp resolve_queue(%Config.Queue{} = queue, prefix, identity, arn_by_topic_name) do
    full_name = full_name(prefix, queue.name, queue.fifo)
    arn = sqs_arn(identity.region, identity.account_id, full_name)
    url = sqs_url(identity.region, identity.account_id, full_name)

    subscribe_to_arns = Enum.map(queue.subscribe_to, &Map.fetch!(arn_by_topic_name, &1))

    %Queue{
      config: queue,
      full_name: full_name,
      arn: arn,
      url: url,
      subscribe_to_arns: subscribe_to_arns,
      dlq: resolve_dlq(queue, prefix, identity)
    }
  end

  defp resolve_dlq(%Config.Queue{dlq: nil}, _prefix, _identity), do: nil

  defp resolve_dlq(%Config.Queue{dlq: dlq_config, fifo: fifo} = queue, prefix, identity) do
    # DLQ inherits FIFO-ness from its parent (AWS requires source and target of
    # a redrive policy to match).
    logical_name = "#{queue.name}#{dlq_config.suffix}" |> String.to_atom()
    full_name = full_name(prefix, logical_name, fifo)

    %Dlq{
      config: dlq_config,
      full_name: full_name,
      arn: sqs_arn(identity.region, identity.account_id, full_name),
      url: sqs_url(identity.region, identity.account_id, full_name)
    }
  end

  defp full_name(prefix, name, fifo?) do
    "#{prefix}_#{name}" |> maybe_fifo(fifo?)
  end

  defp maybe_fifo(base, true), do: base <> ".fifo"
  defp maybe_fifo(base, _), do: base

  defp sns_arn(region, account_id, full_name),
    do: "arn:aws:sns:#{region}:#{account_id}:#{full_name}"

  defp sqs_arn(region, account_id, full_name),
    do: "arn:aws:sqs:#{region}:#{account_id}:#{full_name}"

  defp sqs_url(region, account_id, full_name),
    do: "https://sqs.#{region}.amazonaws.com/#{account_id}/#{full_name}"
end
