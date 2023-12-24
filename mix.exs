defmodule Elasticlunr.MixProject do
  use Mix.Project

  @version "0.6.4"
  @scm_url "https://github.com/heywhy/ex_elasticlunr"

  def project do
    [
      app: :elasticlunr,
      version: @version,
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: [
        files: ["lib", "mix.exs", "CHANGELOG.md", "README.md", "c_src", "Makefile"],
        maintainers: ["Atanda Rasheed"],
        licenses: ["MIT License"],
        links: %{
          "GitHub" => @scm_url,
          "Docs" => "https://hexdocs.pm/elasticlunr"
        }
      ],
      description: """
      Elasticlunr is a lightweight full-text search engine. It's a port of Elasticlunr.js with more improvements.
      """,

      # Compilers
      # compilers: [:elixir_make] ++ Mix.compilers(),

      # Coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_deps: :apps_direct,
        plt_ignore_apps: [:erbloom]
      ],

      # Docs
      name: "Elasticlunr",
      homepage_url: "https://hexdocs.pm/elasticlunr",
      docs: [
        main: "readme",
        extras: ["README.md", "LICENSE"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Elasticlunr.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:benchee, "~> 1.0", only: :dev},
      {:benchee_html, "~> 1.0", only: :dev},
      {:cc_precompiler, "~> 0.1", runtime: false},
      {:credo, "~> 1.5", only: :dev, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:elixir_make, "~> 0.7", runtime: false},
      {:erbloom, github: "filmor/erbloom", branch: "update-rustler"},
      {:ex_doc, "~> 0.25", only: :dev, runtime: false},
      {:excoveralls, "~> 0.14", only: :test},
      {:faker, "~> 0.16", only: :test},
      {:file_system, "~> 0.2"},
      {:flake_id, "~> 0.1"},
      {:git_hooks, "~> 0.7", only: :dev, runtime: false},
      {:git_ops, "~> 2.5", only: :dev},
      {:liveness, "~> 1.0", only: :test},
      {:mimic, "~> 1.7", only: :test},
      {:stemmer, "~> 1.0"},
      {:telemetry, "~> 1.2"},
      {:treex, "~> 0.1"},
      {:uniq, "~> 0.4"}
    ]
  end

  defp aliases do
    [
      "ops.release": ["cmd mix test --color", "git_ops.release"],
      setup: ["deps.get", "git_hooks.install"]
    ]
  end
end
