defmodule Box.LeveledCompactionTest do
  use ExUnit.Case

  alias Box.Fs
  alias Box.LeveledCompaction
  alias Box.SSTable

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
    pid = start_supervised!({LeveledCompaction, opts})

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
    _ = new_sstable(dir)
    _ = new_sstable(dir)
    _ = new_sstable(dir)

    assert eventually(fn -> SSTable.list(dir) |> Enum.count() == 1 end)
  end
end
