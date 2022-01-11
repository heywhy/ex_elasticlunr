defmodule Elasticlunr.MixProject do
  use Mix.Project

  @source_url "https://github.com/heywhy/ex_elasticlunr"

  def project do
    [
      app: :elasticlunr,
      version: "0.6.3",
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      aliases: aliases(),
      deps: deps(),
      source_url: @source_url,

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
      {:jason, "~> 1.3"},
      {:stemmer, "~> 1.0"},
      {:uuid, "~> 1.1"},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.25", only: :dev, runtime: false},
      {:faker, "~> 0.16", only: :test},
      {:mox, "~> 1.0", only: :test}
    ]
  end

  defp aliases do
    [
      test: ~w[format credo test]
    ]
  end

  defp description do
    "Elasticlunr is a lightweight full-text search engine. It's a port of Elasticlunr.js with more improvements."
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md"],
      maintainers: ["Atanda Rasheed"],
      licenses: ["MIT License"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/elasticlunr"
      }
    ]
  end
end
