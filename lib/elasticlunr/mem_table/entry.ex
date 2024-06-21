defmodule Elasticlunr.MemTable.Entry do
  @enforce_keys [:key, :value, :deleted, :timestamp]
  defstruct [:key, :value, :deleted, :timestamp]

  @type t :: %__MODULE__{
          key: binary(),
          value: binary() | nil,
          deleted: boolean(),
          timestamp: pos_integer()
        }
end
