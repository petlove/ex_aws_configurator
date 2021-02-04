defmodule ExAwsConfigurator.Factory do
  use ExMachina

  use ExAwsConfigurator.Factory.Config
  use ExAwsConfigurator.Factory.Queue
  use ExAwsConfigurator.Factory.Topic
end
