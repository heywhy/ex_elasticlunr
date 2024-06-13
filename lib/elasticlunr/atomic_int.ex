defmodule Elasticlunr.AtomicInt do
  @on_load :load

  @type t :: reference()

  def load do
    nif_file = ~c"#{:code.priv_dir(:elasticlunr)}/libnif"

    case :erlang.load_nif(nif_file, 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, reason} -> IO.puts("Failed to load nif: #{reason}")
    end
  end

  @spec new(integer()) :: t()
  def new(value \\ 0), do: init(value)

  @spec fetch_add(t(), non_neg_integer()) :: integer()
  def fetch_add(ref, incr) do
    ref
    |> get()
    |> tap(fn _ -> add(ref, incr) end)
  end

  # nif methods
  def init(_value), do: :erlang.nif_error(:not_loaded)

  @spec get(t()) :: integer()
  def get(_ref), do: :erlang.nif_error(:not_loaded)

  @spec put(t(), integer()) :: :ok
  def put(_ref, _value), do: :erlang.nif_error(:not_loaded)

  @spec add(t(), non_neg_integer()) :: :ok
  def add(_ref, _incr), do: :erlang.nif_error(:not_loaded)

  @spec add_get(t(), non_neg_integer()) :: integer()
  def add_get(_ref, _incr), do: :erlang.nif_error(:not_loaded)

  @spec sub_get(t(), non_neg_integer()) :: integer()
  def sub_get(_ref, _incr), do: :erlang.nif_error(:not_loaded)
end
