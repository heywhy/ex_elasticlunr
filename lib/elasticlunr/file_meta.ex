defmodule Elasticlunr.FileMeta do
  @enforce_keys [:number]
  defstruct [:dir, :number, :smallest_key, :largest_key, size: 0]

  @type t :: %__MODULE__{
          size: integer(),
          number: pos_integer(),
          dir: nil | Path.t(),
          largest_key: nil | binary(),
          smallest_key: nil | binary()
        }
end
