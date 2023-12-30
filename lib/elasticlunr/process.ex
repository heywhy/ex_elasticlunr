defmodule Elasticlunr.Process do
  alias Elasticlunr.Server.Reader
  alias Elasticlunr.Server.Writer

  @registry Elasticlunr.IndexRegistry

  @spec reader(String.t()) :: pid() | nil
  def reader(index) do
    {:via, Registry, {@registry, index}}
    |> Supervisor.which_children()
    |> Enum.find(&(elem(&1, 0) == Reader))
    |> case do
      nil -> nil
      {Reader, pid, :worker, [Reader]} -> pid
    end
  end

  @spec writer(String.t()) :: pid() | nil
  def writer(index) do
    {:via, Registry, {@registry, index}}
    |> Supervisor.which_children()
    |> Enum.find(&(elem(&1, 0) == Writer))
    |> case do
      nil -> nil
      {Writer, pid, :worker, [Writer]} -> pid
    end
  end
end
