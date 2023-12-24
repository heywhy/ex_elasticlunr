defmodule Elasticlunr.Process do
  alias Elasticlunr.Index.ReaderServer
  alias Elasticlunr.Index.WriterServer

  @registry Elasticlunr.IndexRegistry

  @spec reader(binary()) :: pid() | nil
  def reader(index) do
    {:via, Registry, {@registry, index}}
    |> Supervisor.which_children()
    |> Enum.find(&(elem(&1, 0) == ReaderServer))
    |> case do
      nil -> nil
      {ReaderServer, pid, :worker, [ReaderServer]} -> pid
    end
  end

  @spec writer(binary()) :: pid() | nil
  def writer(index) do
    {:via, Registry, {@registry, index}}
    |> Supervisor.which_children()
    |> Enum.find(&(elem(&1, 0) == WriterServer))
    |> case do
      nil -> nil
      {WriterServer, pid, :worker, [WriterServer]} -> pid
    end
  end
end
