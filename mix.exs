defmodule ExAwsConfigurator.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_aws_configurator,
      version: get_version(),
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      deps: deps(),
      package: package(),
      name: "ExAwsConfigurator",
      description: "A json based SNS/SQS configurator for elixir/phoenix projects",
      source_url: "https://github.com/petlove/ex_aws_configurator",
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
      mod: {ExAwsConfigurator.Application, []}
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:ex_aws, "~> 2.6"},
      {:ex_aws_sns, "~> 2.3"},
      {:ex_aws_sqs, "~> 3.4"},
      {:ex_aws_sts, "~> 2.3"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:ex_machina, "~> 2.8", only: [:dev, :test]},
      {:excoveralls, "~> 0.18", only: :test},
      {:hackney, "~> 1.20"},
      {:jason, "~> 1.4"},
      {:mox, "~> 1.2", only: :test},
      {:sweet_xml, "~> 0.7"},
      {:telemetry, "~> 1.3"}
    ]
  end

  defp package do
    [
      name: :ex_aws_configurator,
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/petlove/ex_aws_configurator"},
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG* VERSION*)
    ]
  end
end
