defmodule ExAwsConfigurator.Resolved do
  @moduledoc """
  The declared config decorated with concrete ARNs, URLs and full names.

  This is produced once at boot — it is what the internal ensure pipeline
  consumes and what is cached in `:persistent_term` for runtime lookup by
  `ExAwsConfigurator.publish/3` and `ExAwsConfigurator.send_to_queue/3`.
  """

  defstruct identity: nil, topics: %{}, external_topics: %{}, queues: %{}

  @type t :: %__MODULE__{
          identity: %{account_id: String.t(), region: String.t()},
          topics: %{atom() => __MODULE__.Topic.t()},
          external_topics: %{atom() => __MODULE__.ExternalTopic.t()},
          queues: %{atom() => __MODULE__.Queue.t()}
        }
end

defmodule ExAwsConfigurator.Resolved.Topic do
  @moduledoc """
  Resolved view of a declared resource, carrying both the original declared
  config and the ARN/URL/full_name computed at boot.
  """
  defstruct [:config, :full_name, :arn]

  @type t :: %__MODULE__{
          config: ExAwsConfigurator.Config.Topic.t(),
          full_name: String.t(),
          arn: String.t()
        }
end

defmodule ExAwsConfigurator.Resolved.ExternalTopic do
  @moduledoc """
  Resolved view of a declared resource, carrying both the original declared
  config and the ARN/URL/full_name computed at boot.
  """
  defstruct [:config, :full_name, :arn]

  @type t :: %__MODULE__{
          config: ExAwsConfigurator.Config.ExternalTopic.t(),
          full_name: String.t() | nil,
          arn: String.t()
        }
end

defmodule ExAwsConfigurator.Resolved.Queue do
  @moduledoc """
  Resolved view of a declared resource, carrying both the original declared
  config and the ARN/URL/full_name computed at boot.
  """
  defstruct [:config, :full_name, :arn, :url, :subscribe_to_arns, :dlq]

  @type t :: %__MODULE__{
          config: ExAwsConfigurator.Config.Queue.t(),
          full_name: String.t(),
          arn: String.t(),
          url: String.t(),
          subscribe_to_arns: [String.t()],
          dlq: ExAwsConfigurator.Resolved.Dlq.t() | nil
        }
end

defmodule ExAwsConfigurator.Resolved.Dlq do
  @moduledoc """
  Resolved view of a declared resource, carrying both the original declared
  config and the ARN/URL/full_name computed at boot.
  """
  defstruct [:config, :full_name, :arn, :url]

  @type t :: %__MODULE__{
          config: ExAwsConfigurator.Config.Dlq.t(),
          full_name: String.t(),
          arn: String.t(),
          url: String.t()
        }
end
