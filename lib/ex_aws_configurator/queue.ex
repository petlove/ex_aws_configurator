defmodule ExAwsConfigurator.Queue do
  alias ExAwsConfigurator.Topic

  @type t :: %__MODULE__{
          name: binary(),
          region: binary(),
          environment: binary(),
          prefix: binary(),
          attributes: ExAws.SQS.queue_attributes(),
          topics: [Topic]
        }

  defstruct name: nil,
            environment: Mix.env(),
            region: nil,
            prefix: nil,
            attributes: [
              fifo_queue: false,
              content_based_deduplication: false,
              max_receive_count: 7,
              dead_letter_queue: false,
              dead_letter_queue_suffix: "_failures",
              visibility_timeout: 60,
              message_retention_period: 1_209_600
            ],
            topics: []

  @policy_version '2012-10-17'
  @policy_effect 'Allow'
  @policy_action 'SQS:SendMessage'

  @doc false
  def full_name(%__MODULE__{} = queue) do
    [queue.prefix, queue.environment, queue.name]
    |> Enum.filter(&(!is_nil(&1)))
    |> Enum.join("_")
  end

  @doc false
  def url(%__MODULE__{} = queue) do
    %{scheme: scheme, host: host} = ExAws.Config.new(:sqs)

    ["#{scheme}#{host}", ExAwsConfigurator.get_env(:account_id), full_name(queue)]
    |> Enum.join("/")
  end

  @doc false
  def arn(%__MODULE__{} = queue) do
    ["arn:aws:sqs", queue.region, ExAwsConfigurator.get_env(:account_id), full_name(queue)]
    |> Enum.join(":")
  end

  @doc false
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

  @doc false
  def region(%__MODULE__{} = queue) do
    queue.region || ExAws.Config.new(:sqs).region
  end
end
