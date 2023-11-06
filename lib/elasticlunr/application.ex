defmodule Elasticlunr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Box.Compaction

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, name: Box.Fs, keys: :unique},
      {Registry, name: Elasticlunr.IndexRegistry, keys: :unique},
      {Task.Supervisor, name: Elasticlunr.FlushMemTableSupervisor},
      FlakeIdWorker,
      Compaction.Scheduler
      # Starts a worker by calling: Elasticlunr.Worker.start_link(arg)
      # {Elasticlunr.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Elasticlunr.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
