defmodule Elasticlunr.MixProject do
  use Mix.Project

  def project do
    [
      app: :elasticlunr,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Elasticlunr.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:faker, "~> 0.16", only: :test}
    ]
  end

  defp aliases do
    [
      test: ~w[credo test]
    ]
  end
end
