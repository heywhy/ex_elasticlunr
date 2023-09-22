defmodule Box.Bloom.Stackable do
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

  @ext "bf"

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    # TODO: Allow parameters to be configured by user
    fp_rate = Keyword.get(opts, :fp_rate, 0.01)
    capacity = Keyword.get(opts, :capacity, 1_000_000)

    bloom_filters =
      opts
      |> Keyword.get(:init?, true)
      |> case do
        false -> []
        true -> [Bloom.new_optimal(capacity, fp_rate)]
      end

    attrs = %{
      count: 0,
      fp_rate: fp_rate,
      capacity: capacity,
      bloom_filters: bloom_filters,
      expansion: Keyword.get(opts, :expansion, 2)
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
    :ok = Bloom.set(bf, term)

    struct!(mod, capacity: new_capacity, count: capacity + 1, bloom_filters: [bf] ++ bfs)
  end

  def set(
        %__MODULE__{count: count, bloom_filters: [bf | _bfs]} = mod,
        term
      ) do
    :ok = Bloom.set(bf, term)

    struct!(mod, count: count + 1)
  end

  @spec flush(t(), Path.t()) :: :ok | no_return()
  def flush(%__MODULE__{bloom_filters: bfs} = mod, dir) do
    :ok =
      bfs
      |> Enum.with_index()
      |> Enum.each(fn {bloom_filter, index} ->
        :ok =
          dir
          |> Path.join("#{index}.#{@ext}")
          |> then(&Bloom.flush(bloom_filter, &1))
      end)

    dir
    |> Path.join("_.#{@ext}")
    |> Fs.write(to_binary(mod))
  end

  @spec from_path(Path.t()) :: t()
  def from_path(dir) do
    bloom_filters = list(dir)
    state = Path.join(dir, "_.#{@ext}")

    with fd <- Fs.open(state),
         <<capacity::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         <<fp_rate::unsigned-float>> <- IO.binread(fd, 8),
         <<expansion::unsigned-integer>> <- IO.binread(fd, 1),
         <<count::unsigned-integer-size(64)>> <- IO.binread(fd, 8),
         :ok <- File.close(fd),
         bloom_filters <- Enum.map(bloom_filters, &Bloom.from_path/1),
         opts <- [init?: false, fp_rate: fp_rate, capacity: capacity, expansion: expansion] do
      opts
      |> new()
      |> struct!(count: count, bloom_filters: bloom_filters)
    end
  end

  defp list(dir) do
    Path.expand(dir)
    |> then(&Path.wildcard("#{&1}/*.#{@ext}"))
    |> Enum.reject(&String.ends_with?(&1, "_.#{@ext}"))
  end

  defp to_binary(%__MODULE__{
         fp_rate: fp_rate,
         capacity: capacity,
         count: count,
         expansion: expansion
       }) do
    <<capacity::unsigned-integer-size(64), fp_rate::unsigned-float, expansion,
      count::unsigned-integer-size(64)>>
  end
end
