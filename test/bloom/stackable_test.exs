defmodule Elasticlunr.Bloom.StackableTest do
  use ExUnit.Case, async: true

  alias Box.Bloom.Stackable

  import Elasticlunr.Fixture

  test "set/2" do
    bloom_filter = Stackable.new()
    id = FlakeId.get() |> FlakeId.from_string()

    assert %Stackable{count: 1} = bloom_filter = Stackable.set(bloom_filter, id)
    assert %Stackable{count: 2} = Stackable.set(bloom_filter, "hello")
  end

  test "set/2 increases stack" do
    bloom_filter =
      Stackable.new(capacity: 1)
      |> Stackable.set(FlakeId.get() |> FlakeId.from_string())
      |> Stackable.set(FlakeId.get() |> FlakeId.from_string())

    assert %Stackable{capacity: 2, bloom_filters: bfs} = bloom_filter
    assert Enum.count(bfs) == 2
  end

  test "check?/2" do
    bloom_filter = Stackable.new()
    id = FlakeId.get() |> FlakeId.from_string()

    bloom_filter = Stackable.set(bloom_filter, id)

    assert Stackable.check?(bloom_filter, id)
    refute Stackable.check?(bloom_filter, "unknown")
  end

  test "flush/1" do
    dir = tmp_dir!()
    id1 = FlakeId.get() |> FlakeId.from_string()
    id2 = FlakeId.get() |> FlakeId.from_string()

    bloom_filter =
      Stackable.new(capacity: 1)
      |> Stackable.set(id1)
      |> Stackable.set(id2)

    assert :ok = Stackable.flush(bloom_filter, dir)
  end

  test "from_path/1" do
    dir = tmp_dir!()
    id1 = FlakeId.get() |> FlakeId.from_string()
    id2 = FlakeId.get() |> FlakeId.from_string()

    bloom_filter =
      Stackable.new(capacity: 1)
      |> Stackable.set(id1)
      |> Stackable.set(id2)

    assert :ok = Stackable.flush(bloom_filter, dir)
    assert bloom_filter = Stackable.from_path(dir)
    assert Stackable.check?(bloom_filter, id1)
    assert Stackable.check?(bloom_filter, id2)
  end
end
