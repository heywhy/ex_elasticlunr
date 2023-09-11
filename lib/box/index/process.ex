defmodule Box.Index.Process do
  alias Box.Index.Reader
  alias Box.Index.Writer

  @fs_registry Box.Index.Fs
  @registry Elasticlunr.IndexRegistry

  def fs_watcher(dir), do: GenServer.whereis({:via, Registry, {@fs_registry, dir}})

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
