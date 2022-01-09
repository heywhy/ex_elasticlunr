defmodule Elasticlunr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Elasticlunr.IndexManager

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, name: Elasticlunr.IndexRegistry, keys: :unique},
      {DynamicSupervisor, name: Elasticlunr.IndexSupervisor, strategy: :one_for_one}
      # Starts a worker by calling: Elasticlunr.Worker.start_link(arg)
      # {Elasticlunr.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Elasticlunr.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _} = result ->
        :ok = IndexManager.preload()
        result

      err ->
        err
    end
  end
end
