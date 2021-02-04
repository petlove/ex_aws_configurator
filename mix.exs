defmodule ExAwsConfigurator.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_aws_configurator,
      version: get_version(),
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      deps: deps(),
      package: package(),
      hex: hex(),
      name: "ExAwsConfigurator",
      description: "Some description",
      source_url: "https://github.com/marciotoze/ex_aws_configurator",
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: [
        source_ref: Mix.Project.config()[:version],
        formatters: ["html"]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      env: [
        account_id: {:system, "AWS_ACCOUNT_ID"},
        queues: %{},
        topics: %{}
      ]
    ]
  end

  defp get_version do
    case File.read("VERSION") do
      {:ok, version} -> String.trim(version)
      _ -> "0.0.0-unknown"
    end
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_sns, "~> 2.0"},
      {:ex_aws_sqs, "~> 3.2"},
      {:ex_doc, "~> 0.23", only: :dev, runtime: false},
      {:ex_machina, "~> 2.5.0", only: [:dev, :test]},
      {:excoveralls, "~> 0.10", only: :test},
      {:hackney, "~> 1.9"},
      {:jason, "~> 1.2"},
      {:sweet_xml, "~> 0.6"},
      {:vex, "~> 0.8.0"}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{}
    ]
  end

  defp hex do
    [
      api_url: "http://localhost:4000/api/repos/test_repo",
      api_key: "secret"
    ]
  end
end
