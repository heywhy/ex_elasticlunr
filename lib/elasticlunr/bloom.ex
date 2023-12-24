defmodule Elasticlunr.Bloom do
  # TODO: Find a permanent fix for the erbloom error

  @type t :: reference()
  @type serialized_t :: binary()

  @spec set(t(), term()) :: :ok | boolean()
  defdelegate set(reference, term), to: :bloom

  @spec check?(t() | serialized_t(), term()) :: boolean()
  defdelegate check?(reference, term), to: :bloom, as: :check

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
end
