defmodule Elasticlunr.Compaction.Controller do
  use GenServer

  alias Elasticlunr.BackgroundTaskSupervisor
  alias Elasticlunr.Compaction
  alias Elasticlunr.Manifest.Changes
  alias Elasticlunr.SSTable

  require Logger

  defstruct [:task, count: 0, compactions: []]

  @spec process(Compaction.t()) :: :ok
  def process(%Compaction{} = compaction) do
    GenServer.call(__MODULE__, {:process, compaction})
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__, hibernate_after: 5_000)
  end

  @impl true
  def init([]), do: {:ok, %__MODULE__{}}

  @impl true
  def handle_call(
        {:process, compaction},
        _from,
        %__MODULE__{compactions: compactions, count: count} = state
      ) do
    compactions = [{count, compaction} | compactions]

    %{state | compactions: compactions, count: count + 1}
    |> maybe_start_compaction()
    |> then(&{:reply, :ok, &1})
  end

  @impl true
  def handle_info(
        {ref, {tag, changes}},
        %__MODULE__{task: %Task{ref: ref}, compactions: compactions} = state
      ) do
    Process.demonitor(ref, [:flush])

    {[{_tag, compaction}], compactions} = Enum.split_with(compactions, &match?({^tag, _}, &1))

    # override the changes with what was derived from the merge task
    compaction = %{compaction | changes: changes}

    # TODO: log error
    with true <- Process.alive?(compaction.owner),
         :ok <- GenServer.call(compaction.owner, {:apply_compaction_changes, compaction}) do
      %{state | task: nil, compactions: compactions}
      |> maybe_start_compaction()
      |> then(&{:noreply, &1})
    else
      false ->
        Logger.warning(
          "process for the compaction task is dead #{compaction.dir} @ #{compaction.level}"
        )

        %{state | task: nil, compactions: compactions}
        |> maybe_start_compaction()
        |> then(&{:noreply, &1})
    end
  end

  # TODO: compaction with a single file move to the parent level should
  # be processed first followed by inputs with least total file size
  defp maybe_start_compaction(%{task: nil, compactions: [{tag, compaction} | _]} = state) do
    %{
      dir: dir,
      level: level,
      options: options,
      new_file_number: new_file_number,
      changes: changes
    } = compaction

    opts = [max_file_size: options.max_file_size]
    inputs = Enum.concat(compaction.inputs, compaction.parent_inputs)

    task =
      Task.Supervisor.async_nolink(BackgroundTaskSupervisor, fn ->
        with {:ok, files} <- SSTable.merge(inputs, dir, new_file_number, opts) do
          changes
          |> Changes.add_files(level + 1, files)
          |> Changes.delete_files(inputs)
          |> then(&{tag, &1})
        end
      end)

    %{state | task: task}
  end

  defp maybe_start_compaction(state), do: state
end
