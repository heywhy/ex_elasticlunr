defmodule Box.Bloom.Stackable do
  @moduledoc """
  |--------------------------------------------------------|
  | capacity(8B) | fp_rate(8B) | expansion(1B) | count(8B) |
  |--------------------------------------------------------|

  |-----------------|
  | size(4B) | data |
  |-----------------|
  """

  alias Box.Bloom
  alias Box.Fs

  defstruct [:capacity, :count, :fp_rate, :expansion, :bloom_filters]

  @type t :: %__MODULE__{
          fp_rate: float(),
          count: pos_integer(),
          capacity: pos_integer(),
          expansion: pos_integer(),
          bloom_filters: [Bloom.t()]
        }

  @filename "filter.db"

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

    struct(__MODULE__, attrs)
  end

  @spec check?(t(), term()) :: boolean()
  def check?(%__MODULE__{bloom_filters: bfs}, term), do: Enum.any?(bfs, &Bloom.check?(&1, term))

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

    struct!(mod, count: count + 1)
  end

  @spec flush(t(), Path.t()) :: :ok | no_return()
  def flush(
        %__MODULE__{
          fp_rate: fp_rate,
          capacity: capacity,
          count: count,
          expansion: expansion,
          bloom_filters: bfs
        },
        dir
      ) do
    path = Path.join(dir, @filename)
    stream = Fs.stream(path)

    filters =
      bfs
      |> Stream.map(fn bloom_filter ->
        data = Bloom.serialize(bloom_filter)
        size = byte_size(data)

        <<size::unsigned-integer-size(32), data::binary>>
      end)

    metadata =
      <<capacity::unsigned-integer-size(64), fp_rate::unsigned-float, expansion,
        count::unsigned-integer-size(64)>>

    [metadata]
    |> Stream.concat(filters)
    |> Stream.into(stream)
    |> Stream.run()
  end

  @spec from_path(Path.t()) :: t()
  def from_path(dir) do
    with path <- Path.join(dir, @filename),
         fd <- Fs.open(path),
         opts <- read_metadata(fd),
         bloom_filters <- read_filters(fd),
         :ok <- File.close(fd) do
      struct!(__MODULE__, [bloom_filters: bloom_filters] ++ opts)
    end
  end

  defp read_metadata(fd) do
    with <<capacity::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         <<fp_rate::unsigned-float>> <- IO.binread(fd, 8),
         <<expansion::unsigned-integer>> <- IO.binread(fd, 1),
         <<count::unsigned-integer-size(64)>> <- IO.binread(fd, 8) do
      [fp_rate: fp_rate, capacity: capacity, count: count, expansion: expansion]
    end
  end

  defp read_filters(fd, acc \\ []) do
    with <<size::unsigned-integer-size(32)>> <- IO.binread(fd, 4),
         <<data::binary>> <- IO.binread(fd, size),
         bloom_filter <- Bloom.deserialize(data) do
      read_filters(fd, [bloom_filter] ++ acc)
    else
      :eof -> Enum.reverse(acc)
    end
  end
end
