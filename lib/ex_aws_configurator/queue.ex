defmodule ExAwsConfigurator.QueueAttributes do
  @type t :: ExAws.SQS.queue_attributes()

  defstruct content_based_deduplication: false,
            delay_seconds: 0,
            fifo_queue: false,
            maximum_message_size: 262_144,
            message_retention_period: 1_209_600,
            receive_message_wait_time_seconds: 0,
            policy: nil,
            redrive_policy: nil,
            visibility_timeout: 60
end

defmodule ExAwsConfigurator.QueueOptions do
  @type queue_options :: [
          max_receive_count: integer(),
          dead_letter_queue: boolean(),
          dead_letter_queue_suffix: binary(),
          raw_message_delivery: boolean()
        ]

  defstruct max_receive_count: 7,
            dead_letter_queue: true,
            dead_letter_queue_suffix: "_failures",
            raw_message_delivery: false
end

defmodule ExAwsConfigurator.Queue do
  alias ExAwsConfigurator.{
    QueueAttributes,
    QueueOptions,
    Topic
  }

  @type t :: %__MODULE__{
          name: binary(),
          region: binary(),
          environment: binary(),
          prefix: binary(),
          attributes: QueueAttributes,
          options: QueueOptions,
          topics: [Topic]
        }

  defstruct name: nil,
            environment: nil,
            region: nil,
            prefix: nil,
            attributes: %QueueAttributes{},
            options: %QueueOptions{},
            topics: []

  @doc "get queue full name, its a composition of `prefix + environment + queue.name`"
  @spec full_name(t()) :: String.t()
  def full_name(%__MODULE__{} = queue) do
    [queue.prefix, queue.environment, queue.name]
    |> Enum.filter(&(!is_nil(&1)))
    |> Enum.join("_")
  end

  @doc "get queue url"
  @spec url(t()) :: String.t()
  def url(%__MODULE__{} = queue) do
    %{scheme: scheme, host: host} = ExAws.Config.new(:sqs)

    ["#{scheme}#{host}", ExAwsConfigurator.get_env(:account_id), full_name(queue)]
    |> Enum.join("/")
  end

  @doc "get queue arn"
  @spec arn(t()) :: String.t()
  def arn(%__MODULE__{} = queue) do
    ["arn:aws:sqs", queue.region, ExAwsConfigurator.get_env(:account_id), full_name(queue)]
    |> Enum.join(":")
  end

  @doc false
  @spec policy(t()) :: String.t()
  def policy(%__MODULE__{} = queue) do
    arn = arn(queue)

    ssid =
      queue.topics
      |> Enum.map(& &1.name)
      |> Enum.join("_and_")

    %{
      Version: "2012-10-17",
      Id: "#{arn}/SQSDefaultPolicy",
      Statement: [
        %{
          Sid: "subscription_in_#{ssid}",
          Effect: "Allow",
          Principal: %{AWS: ExAwsConfigurator.get_env(:account_id)},
          Action: "SQS:*",
          Resource: [arn],
          Condition: %{
            ArnLike: %{
              'aws:SourceArn' => Enum.map(queue.topics, &Topic.arn/1)
            }
          }
        }
      ]
    }
    |> Jason.encode!()
  end
end
