defmodule Box.SSTable.Entry do
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

  @spec from(MemTable.Entry.t()) :: t()
  def from(%MemTable.Entry{key: key, value: value, deleted: deleted, timestamp: timestamp}) do
    new(key, value, deleted, timestamp)
  end
end
