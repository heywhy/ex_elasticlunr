defmodule Elasticlunr.Compaction do
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Manifest.Changes

  @enforce_keys [:level]
  defstruct [:level, inputs: [], parent_inputs: [], changes: %Changes{}]

  @type t :: %__MODULE__{
          level: non_neg_integer(),
          changes: Changes.t(),
          inputs: [FileMeta.t()],
          parent_inputs: [FileMeta.t()]
        }
end
