defmodule Box.LeveledCompaction.Level do
  alias Box.SSTable

  @enforce_keys [:ordinal, :max_size]
  defstruct [:ordinal, :max_size, paths: [], size: 0]

  @type t :: %__MODULE__{
          paths: [Path.t()],
          size: non_neg_integer(),
          ordinal: non_neg_integer(),
          max_size: integer() | :infinity
        }

  @spec new(non_neg_integer(), integer() | :infinity) :: t()
  def new(ordinal, max_size) when is_integer(max_size) or max_size == :infinity do
    attrs = %{
      ordinal: ordinal,
      max_size: max_size
    }

    struct!(__MODULE__, attrs)
  end

  @spec includes?(t(), Path.t()) :: boolean()
  def includes?(%__MODULE__{paths: paths}, path), do: Enum.member?(paths, path)

  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{paths: paths}), do: Enum.count(paths)

  def maxed?(%__MODULE__{max_size: :infinity}), do: false
  def maxed?(%__MODULE__{max_size: max_size, size: size}), do: size > max_size

  @spec add_sstable(t(), Path.t()) :: t()
  def add_sstable(%__MODULE__{paths: paths, size: curr_size} = level, path) do
    with false <- Enum.member?(paths, path),
         size <- SSTable.size(path) do
      %{level | size: curr_size + size, paths: [path] ++ paths}
    else
      true -> level
    end
  end

  @spec pop_sstable(t()) :: {Path.t(), t()}
  def pop_sstable(%__MODULE__{size: curr_size, paths: [path | paths]} = level) do
    size = SSTable.size(path)
    {path, %{level | paths: paths, size: curr_size - size}}
  end

  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = level) do
    %{level | size: 0, paths: []}
  end
end
