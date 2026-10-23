defmodule ExAwsConfigurator.QueueAttributes do
  @type t :: ExAws.SQS.queue_attributes()

  defstruct content_based_deduplication: nil,
            delay_seconds: 0,
            fifo_queue: nil,
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
    Account,
    QueueAttributes,
    QueueOptions,
    Topic
  }

  @type t :: %__MODULE__{
          name: binary(),
          region: binary(),
          environment: binary(),
          prefix: binary(),
          separator: binary(),
          attributes: QueueAttributes,
          options: QueueOptions,
          topics: [Topic],
          account: Account.t()
        }

  defstruct name: nil,
            environment: nil,
            region: nil,
            prefix: nil,
            separator: "_",
            attributes: %QueueAttributes{},
            options: %QueueOptions{},
            topics: [],
            account: %Account{}

  @doc "get queue full name, its a composition of `prefix + environment + queue.name`"
  @spec full_name(t()) :: String.t()
  def full_name(%__MODULE__{} = queue) do
    [queue.prefix, queue.environment, queue.name]
    |> Enum.filter(&(!is_nil(&1)))
    |> Enum.join(queue.separator)
  end

  @doc """
  get queue url

  The endpoint (scheme and host) comes from the `ExAws` sqs config; the account id
  comes from the queue account.
  """
  @spec url(t()) :: String.t()
  def url(%__MODULE__{} = queue) do
    %{scheme: scheme, host: host} = ExAws.Config.new(:sqs)

    ["#{scheme}#{host}", queue.account.id, full_name(queue)]
    |> Enum.join("/")
  end

  @doc "get queue arn, composed from the queue region, the id of the queue account and `full_name/1`"
  @spec arn(t()) :: String.t()
  def arn(%__MODULE__{} = queue) do
    ["arn:aws:sqs", queue.region, queue.account.id, full_name(queue)]
    |> Enum.join(":")
  end

  @fifo_suffix ".fifo"

  @doc """
  The dead letter queue of `queue`: a queue of the same account, region and naming parts
  whose name is `queue.name` plus `options.dead_letter_queue_suffix` (a `.fifo` suffix
  is kept at the end, since a fifo queue needs a fifo dead letter queue). It has no
  access policy, no redrive policy, no topics and no dead letter queue of its own.

      iex> queue = %ExAwsConfigurator.Queue{name: :orders, prefix: "app", environment: "prod"}
      iex> ExAwsConfigurator.Queue.full_name(ExAwsConfigurator.Queue.dead_letter_queue(queue))
      "app_prod_orders_failures"

      iex> queue = %ExAwsConfigurator.Queue{name: :"orders.fifo", attributes: %ExAwsConfigurator.QueueAttributes{fifo_queue: true}}
      iex> ExAwsConfigurator.Queue.dead_letter_queue(queue).name
      "orders_failures.fifo"
  """
  @spec dead_letter_queue(t()) :: t()
  def dead_letter_queue(%__MODULE__{attributes: attributes, options: options} = queue) do
    base_name = queue.name |> to_string() |> String.replace_suffix(@fifo_suffix, "")
    suffix = if attributes.fifo_queue, do: @fifo_suffix, else: ""

    %{
      queue
      | name: base_name <> options.dead_letter_queue_suffix <> suffix,
        attributes: %{attributes | policy: nil, redrive_policy: nil},
        options: %{options | dead_letter_queue: false},
        topics: []
    }
  end

  @doc """
  The redrive policy applied to the queue when it has a dead letter queue: after
  `options.max_receive_count` failed receives the message goes to `dead_letter_queue/1`.
  `nil` when `options.dead_letter_queue` is false.
  """
  @spec redrive_policy(t()) :: String.t() | nil
  def redrive_policy(%__MODULE__{options: %QueueOptions{dead_letter_queue: false}}), do: nil

  def redrive_policy(%__MODULE__{options: options} = queue) do
    Jason.encode!(%{
      maxReceiveCount: options.max_receive_count,
      deadLetterTargetArn: queue |> dead_letter_queue() |> arn()
    })
  end

  @doc """
  The access policy applied to the queue: allows every topic the queue subscribes to
  (including topics owned by external accounts) to deliver messages into it.
  """
  @spec policy(t()) :: String.t()
  def policy(%__MODULE__{} = queue) do
    queue_arn = arn(queue)

    %{
      Version: "2012-10-17",
      Statement: [
        %{
          Effect: "Allow",
          Principal: "*",
          Action: "SQS:*",
          Resource: queue_arn,
          Condition: %{
            ArnLike: %{
              "aws:SourceArn": Enum.map(queue.topics, &Topic.arn/1)
            }
          }
        }
      ]
    }
    |> Jason.encode!()
  end
end
