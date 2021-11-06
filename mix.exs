defmodule Elasticlunr.MixProject do
  use Mix.Project

  def project do
    [
      app: :elasticlunr,
      version: "0.1.0",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
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
      {:uuid, "~> 1.1"},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:faker, "~> 0.16", only: :test}
    ]
  end

  defp aliases do
    [
      test: ~w[format credo test]
    ]
  end
end
