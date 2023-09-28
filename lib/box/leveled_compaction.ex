defmodule Box.LeveledCompaction do
  use GenServer

  alias Box.Fs
  alias Box.LeveledCompaction.Level
  alias Box.SSTable

  require Logger

  defstruct [:dir, :exp, :watcher, :files_num_trigger, :max_level1_size, :timer, levels: []]

  # 300mb in bytes
  @max_size 314_572_800
  @filename "lc.db"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, hibernate_after: 5_000)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    dir = Keyword.fetch!(opts, :dir)
    watcher = Fs.watch!(dir)

    attrs = %{
      dir: dir,
      watcher: watcher,
      exp: Keyword.get(opts, :exp, 10),
      files_num_trigger: Keyword.get(opts, :files_num_trigger, 4),
      max_level1_size: Keyword.get(opts, :max_level1_size, @max_size)
    }

    {:ok, struct!(__MODULE__, attrs), {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, %__MODULE__{dir: dir} = state) do
    path = Path.join(dir, @filename)

    case File.exists?(path) do
      false -> {:noreply, state}
      true -> {:noreply, state}
    end
  end

  @impl true
  def handle_info(
        {:compact_level, 0 = ordinal},
        %__MODULE__{dir: dir, levels: levels, max_level1_size: max_size} = state
      ) do
    Logger.info("Compacting level #{ordinal} of #{dir}")

    with %Level{} = level <- Enum.at(levels, 0),
         [path] <- merge_sstables(level.paths, dir) do
      state =
        state
        |> empty_level(0, :infinity)
        |> maybe_add_to_level(path, 1, max_size)

      Logger.info("Finished compacting level 0 of #{dir}")
      {:noreply, state}
    end
  end

  def handle_info(
        {:compact_level, ordinal},
        %__MODULE__{levels: levels, exp: exp, dir: dir} = state
      ) do
    Logger.info("Compacting level #{ordinal} of #{dir}")

    next_ordinal = ordinal + 1
    current_level = Enum.at(levels, ordinal)
    {path, current_level} = Level.pop_sstable(current_level)

    next_level =
      levels
      |> Enum.at(next_ordinal, Level.new(next_ordinal, current_level.max_size * exp))
      |> Level.add_sstable(path)

    state = update_level(state, ordinal, current_level)

    with true <- Level.maxed?(next_level),
         [path] <- merge_sstables(next_level.paths, dir),
         state <- empty_level(state, next_ordinal, next_level.max_size),
         state <- maybe_add_to_level(state, path, next_ordinal, next_level.max_size) do
      Logger.info("Finished compacting level #{ordinal} of #{dir}")
      {:noreply, state}
    else
      _ ->
        Logger.info("Finished compacting level #{ordinal} of #{dir}")
        {:noreply, update_level(state, next_ordinal, next_level)}
    end
  end

  def handle_info(
        {:file_event, watcher, {path, events}},
        %__MODULE__{watcher: watcher, files_num_trigger: max} = state
      ) do
    with true <- SSTable.lockfile?(path),
         path <- Path.dirname(path),
         :create <- Fs.event_to_action(events),
         state <- maybe_add_to_level(state, path, 0, :infinity),
         level <- Enum.at(state.levels, 0) do
      state =
        case Level.count(level) >= max do
          true -> schedule_compaction(state, 0)
          false -> state
        end

      {:noreply, state}
    else
      _ -> {:noreply, state}
    end
  end

  @impl true
  def terminate(:shutdown, %__MODULE__{dir: dir}) do
    Logger.info("Terminating compaction process for #{dir} successfully.")
  end

  def terminate(reason, %__MODULE__{dir: dir}) do
    Logger.warning("Terminating compaction process for #{dir} due to #{inspect(reason)}")
  end

  def update_level(%__MODULE__{levels: levels} = state, ordinal, level) do
    levels
    |> Enum.at(ordinal)
    |> case do
      nil -> %{state | levels: List.insert_at(levels, ordinal, level)}
      _ -> %{state | levels: List.update_at(levels, ordinal, fn _ -> level end)}
    end
  end

  defp empty_level(%__MODULE__{levels: levels} = state, ordinal, max_size) do
    {level, levels} = List.pop_at(levels, ordinal, Level.new(ordinal, max_size))

    %{state | levels: List.insert_at(levels, ordinal, Level.reset(level))}
  end

  defp maybe_add_to_level(%__MODULE__{levels: levels} = state, path, ordinal, max_size) do
    exists? = Enum.any?(levels, &Level.includes?(&1, path))
    {level, levels} = List.pop_at(levels, ordinal, Level.new(ordinal, max_size))

    with false <- exists?,
         level <- Level.add_sstable(level, path),
         state <- %{state | levels: List.insert_at(levels, ordinal, level)} do
      case Level.maxed?(level) do
        true -> schedule_compaction(state, ordinal)
        false -> state
      end
    else
      true -> state
    end
  end

  defp schedule_compaction(%__MODULE__{timer: timer} = state, level) when is_reference(timer) do
    Process.cancel_timer(timer)

    schedule_compaction(%{state | timer: nil}, level)
  end

  defp schedule_compaction(%__MODULE__{timer: nil} = state, level) do
    timer = Process.send_after(self(), {:compact_level, level}, 1_000)

    %{state | timer: timer}
  end

  defp merge_sstables(paths, dir) do
    n = Enum.count(paths) - 1

    paths =
      paths
      |> Enum.sort()
      |> Enum.map(&{&1, 0})

    paths
    |> c(dir, n)
    |> Enum.map(&elem(&1, 0))
  end

  defp c(ss_tables, _dir, 0), do: ss_tables

  defp c(ss_tables, dir, i) do
    {_p, l} = Enum.min_by(ss_tables, &elem(&1, 1))
    {set, rest} = Enum.split_with(ss_tables, &(elem(&1, 1) == l))

    case set do
      [] ->
        c(rest, dir, i - 1)

      [{a, l}, {b, l} | d] ->
        d =
          case d do
            [{path, l}] -> [{path, l + 1}]
            d -> d
          end

        r = SSTable.merge([a, b], dir)

        c([{r, l + 1}] ++ rest ++ d, dir, i - 1)
    end
  end
end
