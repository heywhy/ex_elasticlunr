defmodule Elasticlunr.Bloom.Stackable do
  @moduledoc """
  |--------------------------------------------------------|
  | capacity(8B) | fp_rate(8B) | expansion(1B) | count(8B) |
  |--------------------------------------------------------|

  |-----------------|
  | size(4B) | data |
  |-----------------|
  """

  alias Elasticlunr.Bloom
  alias Elasticlunr.Encoding

  defstruct [:capacity, :count, :fp_rate, :expansion, :bloom_filters]

  @type t :: %__MODULE__{
          fp_rate: float(),
          count: non_neg_integer(),
          capacity: non_neg_integer(),
          expansion: non_neg_integer(),
          bloom_filters: [Bloom.t()]
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    # TODO: Allow parameters to be configured by user
    fp_rate = Keyword.get(opts, :fp_rate, 0.01)
    capacity = Keyword.get(opts, :capacity, 500_000)

    attrs = %{
      count: 0,
      fp_rate: fp_rate,
      capacity: capacity,
      expansion: Keyword.get(opts, :expansion, 2),
      bloom_filters: [Bloom.new_optimal(capacity, fp_rate)]
    }

    struct!(__MODULE__, attrs)
  end

  @spec check?(t(), term()) :: boolean()
  def check?(%__MODULE__{bloom_filters: bfs}, term), do: Enum.any?(bfs, &Bloom.check?(&1, term))

  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{count: count}), do: count

  @spec set(t(), term()) :: t()
  def set(
        %__MODULE__{
          expansion: expansion,
          fp_rate: fp_rate,
          capacity: capacity,
          count: capacity,
          bloom_filters: bfs
        } =
          mod,
        term
      ) do
    new_capacity = capacity * expansion
    bf = Bloom.new_optimal(new_capacity, fp_rate)

    set(%{mod | capacity: new_capacity, bloom_filters: [bf] ++ bfs}, term)
  end

  def set(
        %__MODULE__{count: count, bloom_filters: [bf | _bfs]} = mod,
        term
      ) do
    :ok = Bloom.set(bf, term)

    %{mod | count: count + 1}
  end

  @spec encode(t()) :: iodata()
  def encode(%__MODULE__{
        bloom_filters: bfs,
        fp_rate: fp_rate,
        capacity: capacity,
        count: count,
        expansion: expansion
      }) do
    metadata =
      []
      |> Encoding.put_int64(capacity)
      |> Encoding.put_float(fp_rate)
      |> Encoding.put_int(expansion)
      |> Encoding.put_int64(count)

    bfs
    |> Enum.map(fn bloom_filter ->
      bloom_filter
      |> Bloom.serialize()
      |> then(&Encoding.put_size_prefixed([], &1))
    end)
    |> then(&Enum.concat([metadata], &1))
  end

  @spec decode!(binary()) :: t() | no_return()
  def decode!(binary) when is_binary(binary) do
    {opts, binary} = read_metadata(binary)
    bloom_filters = read_filters(binary)

    struct!(__MODULE__, [bloom_filters: bloom_filters] ++ opts)
  end

  defp read_metadata(binary) do
    {capacity, binary} = Encoding.chop_int64!(binary)
    {fp_rate, binary} = Encoding.chop_float!(binary)
    {expansion, binary} = Encoding.chop_int!(binary)
    {count, binary} = Encoding.chop_int64!(binary)

    {[fp_rate: fp_rate, capacity: capacity, count: count, expansion: expansion], binary}
  end

  defp read_filters(binary, acc \\ [])
  defp read_filters(<<>>, acc), do: Enum.reverse(acc)

  defp read_filters(binary, acc) do
    {data, binary} = Encoding.chop_size_prefixed!(binary)

    data
    |> Bloom.deserialize()
    |> then(&read_filters(binary, [&1] ++ acc))
  end
end
