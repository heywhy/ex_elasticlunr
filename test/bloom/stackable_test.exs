defmodule Elasticlunr.Bloom.StackableTest do
  use ExUnit.Case, async: true

  alias Elasticlunr.Bloom.Stackable
  alias Elasticlunr.Utils

  test "set/2" do
    id = Utils.new_id()
    bloom_filter = Stackable.new()

    assert %Stackable{count: 1} = bloom_filter = Stackable.set(bloom_filter, id)
    assert %Stackable{count: 2} = Stackable.set(bloom_filter, "hello")
  end

  test "set/2 increases stack" do
    bloom_filter =
      Stackable.new(capacity: 1)
      |> Stackable.set(Utils.new_id())
      |> Stackable.set(Utils.new_id())

    assert %Stackable{capacity: 2, bloom_filters: bfs} = bloom_filter
    assert Enum.count(bfs) == 2
  end

  test "check?/2" do
    id = Utils.new_id()
    bloom_filter = Stackable.new()

    bloom_filter = Stackable.set(bloom_filter, id)

    assert Stackable.check?(bloom_filter, id)
    refute Stackable.check?(bloom_filter, "unknown")
  end

  test "encode/1" do
    id1 = Utils.new_id()
    id2 = Utils.new_id()

    bloom_filter =
      Stackable.new(capacity: 1)
      |> Stackable.set(id1)
      |> Stackable.set(id2)

    assert iodata = Stackable.encode(bloom_filter)
    assert IO.iodata_length(iodata) == 194
  end

  test "decode/1" do
    id1 = Utils.new_id()
    id2 = Utils.new_id()

    bloom_filter =
      Stackable.new(capacity: 1)
      |> Stackable.set(id1)
      |> Stackable.set(id2)

    assert iodata = Stackable.encode(bloom_filter)
    assert {:ok, bloom_filter} = Stackable.decode(IO.iodata_to_binary(iodata))
    assert Stackable.check?(bloom_filter, id1)
    assert Stackable.check?(bloom_filter, id2)
  end

  test "decode/1 returns error for invalid binary" do
    assert {:error, :bloom_filter_corruption} = Stackable.decode(<<>>)
  end
end
