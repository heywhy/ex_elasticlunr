defmodule Elasticlunr.Options do
  defstruct max_level: 7,
            l0_compaction_trigger: 4,
            # default to 30mb
            max_file_size: 31_457_280,
            # default to 160mb
            max_buffer_size: 167_772_160,
            # default to 30mb
            max_bytes_for_base_level: 31_457_280,
            max_bytes_for_level_multiplier: 10

  @type t :: %__MODULE__{
          max_level: pos_integer(),
          max_file_size: pos_integer(),
          max_buffer_size: pos_integer(),
          l0_compaction_trigger: pos_integer(),
          max_bytes_for_base_level: pos_integer(),
          max_bytes_for_level_multiplier: pos_integer()
        }
end
