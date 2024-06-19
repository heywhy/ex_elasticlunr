defmodule Elasticlunr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Elasticlunr.Compaction.Controller
  alias Elasticlunr.PubSub

  @impl true
  def start(_type, _args) do
    children = [
      PubSub,
      FlakeIdWorker,
      Controller,
      {Registry, name: Elasticlunr.Fs, keys: :unique},
      {Registry, name: Elasticlunr.IndexRegistry, keys: :unique},
      {Task.Supervisor, name: Elasticlunr.BackgroundTaskSupervisor}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Elasticlunr.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
