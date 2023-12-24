defmodule Elasticlunr.Compaction.LeveledTest do
  use ExUnit.Case

  alias Elasticlunr.Compaction.Leveled
  alias Elasticlunr.Fs
  alias Elasticlunr.SSTable

  import Elasticlunr.Fixture
  import Liveness

  setup context do
    dir = tmp_dir!()

    overrides = context |> Keyword.new() |> Keyword.take([:exp, :files_num_trigger])

    opts =
      [
        dir: dir,
        files_num_trigger: 3,
        max_level1_size: 200
      ]
      |> Keyword.merge(overrides)

    start_supervised!({Fs, dir})
    pid = start_supervised!({Leveled, opts})

    on_exit(fn -> File.rm_rf!(dir) end)

    %{dir: dir, pid: pid}
  end

  test "trigger compaction matching sstables threshold", %{dir: dir, pid: _pid} do
    _ = new_sstable(dir)
    _ = new_sstable(dir)
    _ = new_sstable(dir)

    assert eventually(fn -> SSTable.list(dir) |> Enum.count() == 1 end)
  end

  @tag exp: 2
  test "trigger compaction matching sstables thresholds", %{dir: dir, pid: _pid} do
    Fs.watch!(dir)

    _ = new_sstable(dir)
    _ = new_sstable(dir)
    path = new_sstable(dir)

    wait_for_lockfile_event(path)
    assert_received {:create_lockfile, _dir, _path}
    Process.sleep(5_000)
    assert eventually(fn -> SSTable.list(dir) |> Enum.count() == 1 end)
  end

  defp wait_for_lockfile_event(dir) do
    ss_table_id = Path.basename(dir)

    receive do
      {:file_event, _watcher, {path, events}} ->
        path
        |> SSTable.lockfile?()
        |> Kernel.and(Fs.event_to_action(events) == :create)
        |> Kernel.and(Path.dirname(path) |> String.ends_with?(ss_table_id))
        |> case do
          false -> wait_for_lockfile_event(dir)
          true -> send(self(), {:create_lockfile, Path.dirname(path), path})
        end
    end
  end
end
