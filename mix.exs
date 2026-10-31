defmodule ExAwsConfigurator.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_aws_configurator,
      version: get_version(),
      elixir: "~> 1.15",
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
      env: [
        account_id: {:system, "AWS_ACCOUNT_ID"},
        accounts: %{},
        on_unauthorized: :error,
        queues: %{},
        topics: %{}
      ]
    ]
  end

  # The version comes from the release tag, never this file: EX_AWS_CONFIGURATOR_VERSION
  # when publishing, else the v* tag (own checkout or git dep), else the version Hex
  # recorded when it installed the package, else 0.0.0-dev. Only an exactly tagged
  # checkout gets the tag's version; N commits past v2.0.0 is 2.0.1-dev.N+<sha>, which
  # sorts after 2.0.0 and before 2.0.1.
  defp get_version do
    env_version() || tag_version() || hex_version() || "0.0.0-dev"
  end

  defp env_version do
    case System.get_env("EX_AWS_CONFIGURATOR_VERSION", "") |> String.trim() do
      "" -> nil
      version -> version
    end
  end

  # Only with a .git next to this file: anywhere else git would walk up into whatever
  # repo the dep sits in.
  defp tag_version do
    args = ["describe", "--tags", "--long", "--match", "v*"]

    with true <- File.exists?(Path.join(__DIR__, ".git")),
         {out, 0} <- System.cmd("git", args, cd: __DIR__, stderr_to_stdout: true),
         [_, major, minor, patch, since, sha] <-
           Regex.run(~r/\Av(\d+)\.(\d+)\.(\d+)-(\d+)-g([0-9a-f]+)\z/, String.trim(out)) do
      case since do
        "0" -> "#{major}.#{minor}.#{patch}"
        _ -> "#{major}.#{minor}.#{String.to_integer(patch) + 1}-dev.#{since}+#{sha}"
      end
    else
      _ -> nil
    end
  rescue
    # git isn't installed
    ErlangError -> nil
  end

  # Installed from Hex there's no .git and no env var, but Hex writes the published
  # version to hex_metadata.config in the dep's directory.
  defp hex_version do
    with {:ok, terms} <- :file.consult(Path.join(__DIR__, "hex_metadata.config")),
         {_, version} <- List.keyfind(terms, "version", 0) do
      version
    else
      _ -> nil
    end
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:ex_aws, "~> 2.7"},
      {:ex_aws_sns, "~> 2.3 and >= 2.3.5"},
      {:ex_aws_sqs, "~> 3.2"},
      {:ex_doc, "~> 0.23", only: :dev, runtime: false},
      {:ex_machina, "~> 2.5.0", only: [:dev, :test]},
      {:excoveralls, "~> 0.18", only: :test},
      {:hackney, "~> 4.9"},
      {:jason, "~> 1.2"},
      {:opentelemetry_api, "~> 1.0", optional: true},
      {:sweet_xml, "~> 0.6"},
      {:telemetry, "~> 0.4 or ~> 1.0"},
      {:telemetry_metrics, "~> 0.6 or ~> 1.0", optional: true},
      {:vex, "~> 0.8.0"}
    ]
  end

  defp package do
    [
      name: :ex_aws_configurator,
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/petlove/ex_aws_configurator"},
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*)
    ]
  end
end
