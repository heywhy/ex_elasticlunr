defmodule Box.Bloom do
  # TODO: Find a permanent fix for the erbloom error

  alias Box.Fs

  @type t :: reference()
  @type serialized_t :: binary()

  @spec set(t(), term()) :: :ok | boolean()
  defdelegate set(reference, term), to: :bloom

  @spec check(t() | serialized_t(), term()) :: boolean()
  defdelegate check(reference, term), to: :bloom

  @spec new_optimal(pos_integer(), float()) :: t() | no_return()
  def new_optimal(capacity, fp_rate) do
    {:ok, ref} = :bloom.new_optimal(capacity, fp_rate)
    ref
  end

  @spec serialize(t()) :: serialized_t()
  def serialize(reference) do
    {:ok, bin} = :bloom.serialize(reference)
    bin
  end

  @spec deserialize(serialized_t()) :: t()
  def deserialize(bin) do
    {:ok, reference} = :bloom.deserialize(bin)
    reference
  end

  @spec flush(t(), Path.t()) :: :ok
  def flush(reference, path) do
    reference
    |> serialize()
    |> then(&Fs.write(path, &1))
  end

  @spec from_path(Path.t()) :: t()
  def from_path(path), do: Fs.read(path) |> deserialize()
end
