defmodule ExAwsConfigurator.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:ex_aws_configurator, :auto_setup, true) do
        [ExAwsConfigurator.Bootstrapper]
      else
        []
      end

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: ExAwsConfigurator.Supervisor
    )
  end
end
