defmodule Elasticlunr.FileMeta do
  @enforce_keys [:dir, :number]
  defstruct [:dir, :number, :smallest_key, :largest_key, size: 0]

  @type t :: %__MODULE__{
          dir: Path.t(),
          size: integer(),
          number: pos_integer(),
          largest_key: binary(),
          smallest_key: binary()
        }
end
