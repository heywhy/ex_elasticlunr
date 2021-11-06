defmodule Elasticlunr.Utils.Process do
  @spec child_pid?(tuple, atom) :: boolean
  def child_pid?({:undefined, pid, :worker, [mod]}, mod) when is_pid(pid), do: true
  def child_pid?(_child, _module), do: false

  @spec id_from_pid(tuple, atom, atom) :: [atom | binary]
  def id_from_pid({:undefined, pid, :worker, [mod]}, registry, mod),
    do: Registry.keys(registry, pid)

  @spec active_processes(atom, atom, atom) :: [any()]
  def active_processes(supervisor, registry, module) do
    supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.filter(&child_pid?(&1, module))
    |> Enum.flat_map(&id_from_pid(&1, registry, module))
  end
end
