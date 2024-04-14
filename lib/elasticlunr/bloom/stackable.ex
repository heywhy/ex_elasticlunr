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
      <<capacity::unsigned-integer-size(64), fp_rate::unsigned-float, expansion::unsigned-integer,
        count::unsigned-integer-size(64)>>

    bfs
    |> Enum.map(fn bloom_filter ->
      data = Bloom.serialize(bloom_filter)
      size = byte_size(data)

      <<size::unsigned-integer-size(32), data::binary>>
    end)
    |> then(&Enum.concat([metadata], &1))
  end

  @spec decode(binary()) :: {:ok, t()}
  def decode(binary) when is_binary(binary) do
    with {:ok, opts, binary} when is_list(opts) <- read_metadata(binary),
         bloom_filters when is_list(bloom_filters) <- read_filters(binary) do
      {:ok, struct!(__MODULE__, [bloom_filters: bloom_filters] ++ opts)}
    end
  end

  defp read_metadata(binary) do
    with <<capacity::unsigned-integer-size(64), binary::binary>> <- binary,
         <<fp_rate::unsigned-float, binary::binary>> <- binary,
         <<expansion::unsigned-integer, binary::binary>> <- binary,
         <<count::unsigned-integer-size(64), binary::binary>> <- binary do
      {:ok, [fp_rate: fp_rate, capacity: capacity, count: count, expansion: expansion], binary}
    else
      _ -> {:error, :bloom_filter_corruption}
    end
  end

  defp read_filters(binary, acc \\ [])
  defp read_filters(<<>>, acc), do: Enum.reverse(acc)

  defp read_filters(binary, acc) do
    with <<size::unsigned-integer-size(32), binary::binary>> <- binary,
         <<data::binary-size(size), binary::binary>> <- binary,
         bloom_filter <- Bloom.deserialize(data) do
      read_filters(binary, [bloom_filter] ++ acc)
    end
  end
end
