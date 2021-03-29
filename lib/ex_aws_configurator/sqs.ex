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
    queue = ExAwsConfigurator.get_queue(queue_name)

    queue =
      if queue.options.dead_letter_queue do
        create_dead_letter_queue(queue, tags)
      else
        queue
      end

    full_name = Queue.full_name(queue)

    Logger.info(~s"""
    \n\n  Creating queue #{full_name} on #{queue.region}
        Attributes:
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} delay_seconds: #{queue.attributes.delay_seconds}
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} maximum_message_size: #{
      queue.attributes.maximum_message_size
    }
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} message_retention_period: #{
      queue.attributes.message_retention_period
    }
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} receive_message_wait_time_seconds: #{
      queue.attributes.receive_message_wait_time_seconds
    }
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} visibility_timeout: #{
      queue.attributes.visibility_timeout
    }
        Options:
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} dead_letter_queue: #{
      queue.options.dead_letter_queue
    }
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} dead_letter_queue_suffix: #{
      queue.options.dead_letter_queue_suffix
    }
          #{IO.ANSI.green()}>#{IO.ANSI.reset()} max_receive_count: #{
      queue.options.max_receive_count
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
  def send_message(queue_name, message, opts) when is_atom(queue_name) do
    queue = ExAwsConfigurator.get_queue(queue_name)

    Logger.info("Sending message to #{Queue.full_name(queue)}")

    queue
    |> Queue.url()
    |> SQS.send_message(message, opts)
    |> ExAws.request(region: queue.region)
  end

  defp create_dead_letter_queue(%Queue{attributes: attributes, options: options} = queue, tags) do
    full_name = Queue.full_name(queue) <> options.dead_letter_queue_suffix

    dead_letter_queue =
      struct(queue, %{attributes: struct(attributes, %{redrive_policy: nil, policy: nil})})

    create_queue_on_sqs(full_name, dead_letter_queue, tags)

    redrive_policy =
      Jason.encode!(%{
        maxReceiveCount: options.max_receive_count,
        deadLetterTargetArn: Queue.arn(queue) <> options.dead_letter_queue_suffix
      })

    struct(queue, %{attributes: struct(queue.attributes, %{redrive_policy: redrive_policy})})
  end

  defp create_queue_on_sqs(full_name, queue, tags) do
    attributes =
      queue.attributes
      |> Map.from_struct()
      |> Enum.filter(&is_nil/1)

    full_name
    |> SQS.create_queue(attributes, tags)
    |> ExAws.request(region: queue.region)
  end
end
