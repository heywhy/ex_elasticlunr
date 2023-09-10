defmodule Box.MemTable do
  alias Box.MemTable.Entry

  alias __MODULE__.Iterator

  @enforce_keys [:entries]
  defstruct [:entries, size: 0]

  @otp_app :elasticlunr

  # default to 15mb
  @max_size 15_728_640

  @type t :: %__MODULE__{
          size: pos_integer(),
          entries: :gb_trees.tree(binary(), Entry.t())
        }

  @spec new() :: t()
  def new do
    struct!(__MODULE__, entries: :gb_trees.empty())
  end

  @spec length(t()) :: pos_integer()
  def length(%__MODULE__{entries: entries}), do: :gb_trees.size(entries)

  @spec size(t()) :: pos_integer()
  def size(%__MODULE__{size: size}), do: size

  @spec maxed?(t()) :: boolean()
  def maxed?(%__MODULE__{size: size}) do
    @otp_app
    |> Application.get_env(:mem_table_max_size, @max_size)
    |> Kernel.<=(size)
  end

  @spec flush(t(), Path.t()) :: :ok | no_return()
  def flush(%__MODULE__{entries: entries}, dir) do
    now = System.os_time(:microsecond)
    dir = Path.join(dir, "_segments")
    path = Path.join(dir, "#{now}.seg")

    unless File.dir?(dir) do
      :ok = File.mkdir!(dir)
    end

    :gb_trees.to_list(entries)
    |> Stream.map(&elem(&1, 1))
    |> Stream.map(&to_binary(&1))
    |> Stream.into(File.stream!(path, [:append]))
    |> Stream.run()
  end

  @spec list(Path.t()) :: [Path.t()]
  def list(dir) do
    dir
    |> Path.join("_segments")
    |> then(&Path.wildcard("#{&1}/*.seg"))
  end

  @spec from_file(Path.t()) :: t() | no_return()
  def from_file(path) do
    Iterator.new(path)
    |> Enum.reduce(new(), fn %Entry{} = entry, mem_table ->
      case entry.deleted do
        true -> remove(mem_table, entry.key, entry.timestamp)
        false -> set(mem_table, entry.key, entry.value, entry.timestamp)
      end
    end)
  end

  @spec get(t(), binary(), Path.t()) :: Entry.t() | nil
  def get(%__MODULE__{} = mem_table, key, dir) do
    fun = fn path, key, acc ->
      Iterator.new(path)
      |> Enum.find(&(&1.key == key))
      # TODO: Find a more efficient approach
      # Since loading all entries isn't efficient for a situation where
      # there are a thousand entries but key is in 100th row. There should
      # be a balance of usage between row or binary search by the tree.
      |> case do
        nil -> {:cont, acc}
        %Entry{} = entry -> {:halt, entry}
      end
    end

    mem_table
    |> get(key)
    |> case do
      %Entry{} = entry -> entry
      nil -> list(dir) |> Enum.reverse() |> Enum.reduce_while(nil, &fun.(&1, key, &2))
    end
  end

  @spec get(t(), binary()) :: Entry.t() | nil
  def get(%__MODULE__{entries: entries}, key) do
    case :gb_trees.lookup(key, entries) do
      :none -> nil
      {:value, entry} -> entry
    end
  end

  @spec set(t(), binary(), binary(), pos_integer()) :: t()
  def set(%__MODULE__{entries: entries, size: size} = mem_table, key, value, timestamp) do
    case :gb_trees.lookup(key, entries) do
      :none ->
        size = size + byte_size(key) + byte_size(value) + 16 + 1
        entry = Entry.new(key, value, false, timestamp)

        entries = :gb_trees.insert(key, entry, entries)

        %{mem_table | entries: entries, size: size}

      {:value, entry} ->
        size =
          case byte_size(value) < byte_size(entry.value) do
            true -> size - byte_size(entry.value) - byte_size(value)
            false -> size + byte_size(value) - byte_size(entry.value)
          end

        entry = %{entry | value: value, deleted: false, timestamp: timestamp}
        entries = :gb_trees.update(key, entry, entries)

        %{mem_table | entries: entries, size: size}
    end
  end

  @spec remove(t(), binary(), pos_integer()) :: t()
  def remove(%__MODULE__{entries: entries, size: size} = mem_table, key, timestamp) do
    case :gb_trees.lookup(key, entries) do
      :none ->
        size = size + byte_size(key) + 16 + 1

        entry = Entry.new(key, nil, true, timestamp)
        entries = :gb_trees.insert(key, entry, entries)

        %{mem_table | entries: entries, size: size}

      {:value, entry} ->
        size = size - byte_size(entry.value)

        entry = %{entry | value: nil, deleted: true, timestamp: timestamp}
        entries = :gb_trees.update(key, entry, entries)

        %{mem_table | entries: entries, size: size}
    end
  end

  defp to_binary(%Entry{deleted: true, key: key, timestamp: timestamp}) do
    key_size = byte_size(key)
    key_size_data = <<key_size::unsigned-integer-size(64)>>

    deleted_data = <<1::unsigned-integer>>

    timestamp_data = <<timestamp::big-unsigned-integer-size(64)>>

    sizes_data = <<key_size_data::binary, deleted_data::binary>>

    <<sizes_data::binary, key::binary, timestamp_data::binary>>
  end

  defp to_binary(%Entry{deleted: false, key: key, value: value, timestamp: timestamp}) do
    key_size = byte_size(key)
    key_size_data = <<key_size::unsigned-integer-size(64)>>

    deleted_data = <<0::unsigned-integer>>

    timestamp_data = <<timestamp::big-unsigned-integer-size(64)>>

    value_size = byte_size(value)
    value_size_data = <<value_size::unsigned-integer-size(64)>>

    sizes_data = <<key_size_data::binary, deleted_data::binary, value_size_data::binary>>

    kv_data = <<key::binary, value::binary>>

    <<sizes_data::binary, kv_data::binary, timestamp_data::binary>>
  end
end
