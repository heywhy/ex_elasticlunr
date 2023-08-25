defmodule Box.Wal.Entry do
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
end
