defmodule Elasticlunr.Wal.Entry do
  @moduledoc """
  |----------------------------------------------------|
  | timestamp(8B) | key_size(8B) | tombstone(1B) | key |
  |----------------------------------------------------|

  |-----------------------------------------------------------------------------|
  | timestamp(8B) | key_size(8B) | tombstone(1B) | value_size(8B) | key | value |
  |-----------------------------------------------------------------------------|
  """

  alias Elasticlunr.Encoding

  @enforce_keys [:key, :value, :deleted, :timestamp]
  defstruct [:key, :value, :deleted, :timestamp]

  @type t :: %__MODULE__{
          key: binary(),
          value: term() | nil,
          deleted: boolean(),
          timestamp: pos_integer()
        }

  @spec new(binary(), term() | nil, boolean() | pos_integer(), pos_integer()) :: t()
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

  @spec encode(t()) :: iodata()
  def encode(%__MODULE__{deleted: deleted, key: key, value: value, timestamp: timestamp}) do
    iodata =
      []
      |> Encoding.put_boolean(deleted)
      |> Encoding.put_int64(timestamp)
      |> Encoding.put_size_prefixed(key)

    case deleted do
      true -> iodata
      false -> Encoding.put_size_prefixed(iodata, value)
    end
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

  @spec read!(File.io_device()) :: t() | no_return()
  def read!(fd) do
    deleted = Encoding.get_boolean!(fd)
    timestamp = Encoding.get_int64!(fd)

    case deleted do
      true ->
        fd
        |> Encoding.get_size_prefixed!()
        |> then(&new(&1, nil, true, timestamp))

      false ->
        key = Encoding.get_size_prefixed!(fd)
        value = Encoding.get_size_prefixed!(fd)

        new(key, value, false, timestamp)
    end
  end
end
