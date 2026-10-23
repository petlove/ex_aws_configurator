defmodule ExAwsConfigurator.Factory do
  use ExMachina

  use ExAwsConfigurator.Factory.Config
  use ExAwsConfigurator.Factory.Queue
  use ExAwsConfigurator.Factory.Topic

  @doc "Unique per `mix test` run; see `test/test_helper.exs`."
  def run_id, do: :persistent_term.get({__MODULE__, :run_id})
end
