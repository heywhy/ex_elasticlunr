defmodule Elasticlunr.Process do
  alias Elasticlunr.Index.Reader
  alias Elasticlunr.Index.Writer

  @registry Elasticlunr.IndexRegistry

  @spec reader(binary()) :: pid() | nil
  def reader(index) do
    {:via, Registry, {@registry, index}}
    |> Supervisor.which_children()
    |> Enum.find(&(elem(&1, 0) == Reader))
    |> case do
      nil -> nil
      {Reader, pid, :worker, [Reader]} -> pid
    end
  end

  @spec writer(binary()) :: pid() | nil
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
