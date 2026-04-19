defmodule ExAwsConfigurator.Aws.Identity do
  @moduledoc """
  Resolves the AWS account id and region for the current credentials.

  Called once at boot — the result is cached in the Registry — so the STS
  round-trip only happens during bootstrapping. Implemented as a behaviour so
  tests can swap in a fake without stubbing ExAws directly.
  """

  @callback fetch!() :: %{account_id: String.t(), region: String.t()}

  @spec fetch!() :: %{account_id: String.t(), region: String.t()}
  def fetch! do
    impl().fetch!()
  end

  defp impl do
    Application.get_env(:ex_aws_configurator, :identity_impl, __MODULE__.Default)
  end
end

defmodule ExAwsConfigurator.Aws.Identity.Default do
  @moduledoc false
  @behaviour ExAwsConfigurator.Aws.Identity

  @impl true
  def fetch! do
    case ExAws.STS.get_caller_identity() |> ExAws.request() do
      {:ok, %{body: %{account: account_id}}} ->
        %{account_id: account_id, region: ExAws.Config.new(:sts).region}

      {:error, reason} ->
        raise "ex_aws_configurator: failed to resolve AWS identity via STS: #{inspect(reason)}"
    end
  end
end
