defmodule Box.Compaction.LeveledTest do
  use ExUnit.Case

  alias Box.Compaction.Leveled
  alias Box.Fs

  import Elasticlunr.Fixture

  setup do
    dir = tmp_dir!()
    opts = [dir: dir]

    start_supervised!({Fs, dir})
    pid = start_supervised!({Leveled, opts})

    [pid: pid]
  end

  test "hello world", %{pid: pid} do
    assert Process.alive?(pid)
  end
end
