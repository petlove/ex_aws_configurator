defmodule ExAwsConfigurator.NoResultsError do
  defexception [:type, :name, :message]

  def message(%{type: type, name: name}) when not is_nil(type) and not is_nil(name) do
    "the configuration for #{type} `#{name}` is not set"
  end

  def message(%{name: name}) when not is_nil(name) do
    "not found any configuration with key #{name}"
  end
end
