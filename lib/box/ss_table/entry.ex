defmodule Box.SSTable.Entry do
  @moduledoc """
  |----------------------------------------------------|
  | timestamp(8B) | key_size(8B) | tombstone(1B) | key |
  |----------------------------------------------------|

  |-----------------------------------------------------------------------------|
  | timestamp(8B) | key_size(8B) | tombstone(1B) | value_size(8B) | key | value |
  |-----------------------------------------------------------------------------|
  """

  alias Box.MemTable

  @enforce_keys [:key, :value, :deleted, :timestamp]
  defstruct [:key, :value, :deleted, :timestamp]

  @type t :: %__MODULE__{
          key: binary(),
          value: binary() | nil,
          deleted: boolean(),
          timestamp: pos_integer()
        }

  @spec new(binary(), binary() | nil, boolean() | pos_integer(), pos_integer()) :: t()
  def new(key, value, deleted, timestamp) when is_integer(deleted) do
    deleted =
      case deleted do
        0 -> false
        1 -> true
      end

    new(key, value, deleted, timestamp)
  end

  def new(key, value, deleted, timestamp) do
    attrs = %{
      key: key,
      value: value,
      deleted: deleted,
      timestamp: timestamp
    }

    struct!(__MODULE__, attrs)
  end

  @spec from(MemTable.Entry.t() | binary()) :: t()
  def from(%MemTable.Entry{key: key, value: value, deleted: deleted, timestamp: timestamp}) do
    new(key, value, deleted, timestamp)
  end

  def from(entry) when is_binary(entry) do
    case entry do
      <<
        timestamp::big-unsigned-integer-size(64),
        key_size::unsigned-integer-size(64),
        1,
        key::binary-size(key_size)
      >> ->
        new(key, nil, true, timestamp)

      <<timestamp::big-unsigned-integer-size(64), key_size::unsigned-integer-size(64), 0,
        value_size::unsigned-integer-size(64), key::binary-size(key_size),
        value::binary-size(value_size)>> ->
        new(key, value, false, timestamp)
    end
  end

  @spec to_binary(t()) :: binary()
  def to_binary(%__MODULE__{deleted: true, key: key, timestamp: timestamp}) do
    key_size = byte_size(key)
    key_size_data = <<key_size::unsigned-integer-size(64)>>

    timestamp_data = <<timestamp::big-unsigned-integer-size(64)>>

    sizes_data = <<key_size_data::binary, 1>>

    <<timestamp_data::binary, sizes_data::binary, key::binary>>
  end

  def to_binary(%__MODULE__{deleted: false, key: key, value: value, timestamp: timestamp}) do
    key_size = byte_size(key)
    key_size_data = <<key_size::unsigned-integer-size(64)>>

    timestamp_data = <<timestamp::big-unsigned-integer-size(64)>>

    value_size = byte_size(value)
    value_size_data = <<value_size::unsigned-integer-size(64)>>

    sizes_data = <<key_size_data::binary, 0, value_size_data::binary>>

    kv_data = <<key::binary, value::binary>>

    <<timestamp_data::binary, sizes_data::binary, kv_data::binary>>
  end

  @spec size(t()) :: pos_integer()
  def size(%__MODULE__{key: key, deleted: deleted, value: value}) do
    # timestamp_size + key_size + delete_tombstone + key
    default = 8 + 8 + 1 + byte_size(key)

    case deleted do
      true -> default
      false -> default + 8 + byte_size(value)
    end
  end

  @spec read(File.io_device()) :: t()
  def read(fd) do
    with <<timestamp::big-unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         <<key_size::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         <<deleted::unsigned-integer>> <- IO.binread(fd, 1),
         {key, value} <- read_kv(fd, deleted, key_size) do
      new(key, value, deleted, timestamp)
    end
  end

  defp read_kv(fd, 0, key_size) do
    with <<value_size::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         key <- IO.binread(fd, key_size),
         value <- IO.binread(fd, value_size) do
      {key, value}
    end
  end

  defp read_kv(fd, 1, key_size) do
    with key <- IO.binread(fd, key_size) do
      {key, nil}
    end
  end
end
