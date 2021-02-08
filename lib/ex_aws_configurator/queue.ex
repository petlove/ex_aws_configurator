defmodule ExAwsConfigurator.Queue do
  alias ExAwsConfigurator.Topic

  @type queue_options :: [
          dead_letter_queue: boolean(),
          dead_letter_queue_suffix: binary()
        ]

  @type t :: %__MODULE__{
          name: binary(),
          region: binary(),
          environment: binary(),
          prefix: binary(),
          attributes: ExAws.SQS.queue_attributes(),
          options: queue_options(),
          topics: [Topic]
        }

  defstruct name: nil,
            environment: Mix.env(),
            region: System.get_env("AWS_REGION"),
            prefix: nil,
            attributes: [
              fifo_queue: false,
              content_based_deduplication: false,
              visibility_timeout: 60,
              message_retention_period: 1_209_600
            ],
            options: [
              dead_letter_queue: false,
              dead_letter_queue_suffix: "_failures"
            ],
            topics: []

  @policy_version '2012-10-17'
  @policy_effect 'Allow'
  @policy_action 'SQS:SendMessage'

  @doc "get queue full name, its a composition of `prefix + environment + queue.name`"
  @spec full_name(Queue.t()) :: String.t()
  def full_name(%__MODULE__{} = queue) do
    [queue.prefix, queue.environment, queue.name]
    |> Enum.filter(&(!is_nil(&1)))
    |> Enum.join("_")
  end

  @doc "get queue url"
  @spec url(Queue.t()) :: String.t()
  def url(%__MODULE__{} = queue) do
    %{scheme: scheme, host: host} = ExAws.Config.new(:sqs)

    ["#{scheme}#{host}", ExAwsConfigurator.get_env(:account_id), full_name(queue)]
    |> Enum.join("/")
  end

  @doc "get queue arn"
  @spec arn(Queue.t()) :: String.t()
  def arn(%__MODULE__{} = queue) do
    ["arn:aws:sqs", queue.region, ExAwsConfigurator.get_env(:account_id), full_name(queue)]
    |> Enum.join(":")
  end

  @doc false
  @spec policy(Queue.t()) :: String.t()
  def policy(%__MODULE__{} = queue) do
    arn = arn(queue)

    ssid =
      queue.topics
      |> Enum.map(& &1.name)
      |> Enum.join("_and_")

    %{
      Version: @policy_version,
      Id: "#{arn}/SQSDefaultPolicy",
      Statement: [
        %{
          Sid: "subscription_in_#{ssid}",
          Effect: @policy_effect,
          Principal: %{AWS: "*"},
          Action: @policy_action,
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
