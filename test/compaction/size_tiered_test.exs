defmodule ElasticlunrCompaction.SizeTieredTest do
  use ExUnit.Case

  alias Elasticlunr.Compaction.SizeTiered
  alias Elasticlunr.Fs

  import Elasticlunr.Fixture

  setup do
    dir = tmp_dir!()
    opts = [dir: dir]

    start_supervised!({Fs, dir})
    pid = start_supervised!({SizeTiered, opts})

    [pid: pid]
  end

  test "hello world", %{pid: pid} do
    assert Process.alive?(pid)
  end
end
