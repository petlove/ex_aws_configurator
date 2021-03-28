defmodule ExAwsConfigurator.SQS do
  require Logger

  alias ExAwsConfigurator.{Queue, Topic}
  alias ExAws.{SNS, SQS}

  @doc """
  Create an sqs queue based on ex_aws_configurator configuration, that method do NOT subscribe on any topic

  raises `ExAwsConfigurator.NoResultsError` if no configuration was found.

  for the example below, we will consider the following settings

      # config/config.exs

      config :ex_aws_configurator,
        ...
        queues: %{
          an_queue: %{
            environment: "environment",
            region: "us-east-1",
            prefix: "queue_prefix",
            topics: [:an_topic]
          }
        },
        topics: %{
          an_topic: %{
            region: "us-east-1",
            prefix: "topic_prefix",
            environment: "environment"
          }
        }

  ## Examples

      ExAwsConfigurator.create_queue(:queue_name)
      #=> {:ok, term()}

  will create an queue named `prefix + environment + map_key`, the result will be _queue_prefix_environment_an_queue_ on region _us-east-1_

  the response term() will be the `ExAws` response without any modification

      ExAwsConfigurator.get_queue(:not_exist)
      #=> ** (ExAwsConfigurator.NoResultsError) the configuration for queue not_exist is not set

  """
  def create_queue(queue, tags \\ %{})

  @spec create_queue(atom, map) :: {:ok, term} | {:error, term}
  def create_queue(queue_name, tags) when is_atom(queue_name) do
    queue_name
    |> ExAwsConfigurator.get_queue()
    |> create_queue(tags)
  end

  @spec create_queue(Queue.t(), map) :: {:ok, term} | {:error, term}
  def create_queue(%Queue{} = queue, tags) when is_map(tags) do
    queue =
      if Keyword.get(queue.options, :dead_letter_queue) do
        create_dead_letter_queue(queue, tags)
      else
        queue
      end

    full_name = Queue.full_name(queue)

    Logger.info(~s"""
    \n\n  Creating queue #{full_name} on #{queue.region}
        Attributes:
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} delay_seconds: #{queue.attributes[:delay_seconds]}
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} maximum_message_size: #{
      queue.attributes[:maximum_message_size]
    }
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} message_retention_period: #{
      queue.attributes[:message_retention_period]
    }
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} receive_message_wait_time_seconds: #{
      queue.attributes[:receive_message_wait_time_seconds]
    }
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} visibility_timeout: #{
      queue.attributes[:visibility_timeout]
    }
        Options:
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} dead_letter_queue: #{
      queue.options[:dead_letter_queue]
    }
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} dead_letter_queue_suffix: #{
      queue.options[:dead_letter_queue_suffix]
    }
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} max_receive_count: #{
      queue.options[:max_receive_count]
    }
    """)

    create_queue_on_sqs(full_name, queue, tags)
  end

  @doc """
    Subscribe an queue into an topic based on clan configuration
  """
  @spec subscribe(atom, atom) :: {:ok, term} | {:error, term}
  def subscribe(queue_name, topic_name) when is_atom(topic_name) and is_atom(queue_name) do
    queue = ExAwsConfigurator.get_queue(queue_name)
    topic = ExAwsConfigurator.get_topic(topic_name)

    subscribe(queue, topic)
  end

  @spec subscribe(Queue.t(), Topic.t()) :: {:ok, term} | {:error, term}
  def subscribe(%Queue{} = queue, %Topic{} = topic) do
    Logger.info("Subscribe queue #{Queue.full_name(queue)} to topic #{Topic.full_name(topic)}")

    topic
    |> Topic.arn()
    |> SNS.subscribe("sqs", Queue.arn(queue))
    |> ExAws.request(region: topic.region)
  end

  @doc """
  Send message to a queue build the correct queue name based on queue configuration

  raises `ExAwsConfigurator.NoResultsError` if no configuration was found.

  for the example below, we will consider the following settings

      # config/config.exs

      config :ex_aws_configurator,
        ...
        queues: %{
          an_queue: %{
            environment: "environment",
            region: "us-east-1",
            prefix: "queue_prefix",
            topics: [:an_topic]
          }
        }

  ## Examples

      ExAwsConfigurator.send_message(:an_queue, "message")
      #=> {:ok, term()}

  will send a message to queue named _queue_prefix_environment_an_queue_ on region _us-east-1_

  the response term() will be the `ExAws` response without any modification

      ExAwsConfigurator.send_message(:not_exist)
      #=> ** (ExAwsConfigurator.NoResultsError) the configuration for queue not_exist is not set

  another possible error is when configuration exists but queue is not created, in this case the response will be {:error, %{status_code: 404, ...}} returned by AWS response

      ExAwsConfigurator.send_message(:not_exist)
      #=> {:error, term()}
  """
  def send_message(queue_name, message, opts \\ [])

  @spec send_message(atom, String.t(), SQS.sqs_message_opts()) :: {:ok, term} | {:error, term}
  def send_message(queue_name, message, opts)
      when is_atom(queue_name) and is_binary(message) do
    queue_name
    |> ExAwsConfigurator.get_queue()
    |> send_message(message, opts)
  end

  @spec send_message(Queue.t(), String.t(), SQS.sqs_message_opts()) ::
          {:ok, term} | {:error, term}
  def send_message(%Queue{} = queue, message, opts)
      when is_binary(message) and is_list(opts) do
    Logger.info("Sending message to #{Queue.full_name(queue)}")

    queue
    |> Queue.url()
    |> SQS.send_message(message, opts)
    |> ExAws.request(region: queue.region)
  end

  defp create_dead_letter_queue(%Queue{options: opts} = queue, tags) do
    dead_letter_queue_suffix = Keyword.get(opts, :dead_letter_queue_suffix)
    full_name = Queue.full_name(queue) <> dead_letter_queue_suffix
    max_receive_count = Keyword.get(opts, :max_receive_count)

    create_queue_on_sqs(full_name, queue, tags)

    attributes =
      Keyword.merge(
        queue.attributes,
        redrive_policy:
          Jason.encode!(%{
            maxReceiveCount: max_receive_count,
            deadLetterTargetArn: Queue.arn(queue) <> dead_letter_queue_suffix
          })
      )

    struct(queue, %{attributes: attributes})
  end

  defp create_queue_on_sqs(full_name, queue, tags) do
    full_name
    |> SQS.create_queue(queue.attributes, tags)
    |> ExAws.request(region: queue.region)
  end
end
