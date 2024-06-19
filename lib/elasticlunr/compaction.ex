defmodule Elasticlunr.Compaction do
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Manifest.Changes
  alias Elasticlunr.Options

  @enforce_keys [:level, :new_file_number, :options]
  defstruct [
    :dir,
    :level,
    :options,
    :owner,
    :new_file_number,
    inputs: [],
    parent_inputs: [],
    changes: %Changes{}
  ]

  @type t :: %__MODULE__{
          owner: nil | pid(),
          dir: nil | Path.t(),
          level: non_neg_integer(),
          options: Options.t(),
          changes: Changes.t(),
          inputs: [FileMeta.t()],
          parent_inputs: [FileMeta.t()],
          new_file_number: (-> pos_integer())
        }
end
