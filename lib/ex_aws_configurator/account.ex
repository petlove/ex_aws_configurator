defmodule ExAwsConfigurator.Account do
  @moduledoc """
  An AWS account known to the configurator.

  The default account is built from the `account_id` and `region` keys of the
  `:ex_aws_configurator` application env. Extra accounts (for example, an account
  owned by another business unit) are declared under the `accounts` key:

      config :ex_aws_configurator,
        account_id: "000000000000",
        region: "us-east-1",
        accounts: %{
          health: %{id: "111111111111", region: "sa-east-1"}
        }

  A topic can then reference an account by name with `account: :health`.
  Resources that belong to an account other than the default one are **external**:
  the configurator computes their ARN but never creates them, since they are
  managed by their owner.
  """

  @type t :: %__MODULE__{
          name: atom(),
          id: binary() | nil,
          region: binary() | nil
        }

  defstruct name: :default, id: nil, region: nil
end
