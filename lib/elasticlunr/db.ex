defmodule Elasticlunr.DB do
  defstruct [:name, :options]

  @type t :: %__MODULE__{
          name: atom(),
          options: list(atom())
        }

  @spec init(atom(), list()) :: t()
  def init(name, opts \\ []) when is_atom(name) do
    default = ~w[compressed named_table]a
    options = Enum.uniq(default ++ opts)

    unless Enum.member?(:ets.all(), name) do
      :ets.new(name, options)
    end

    struct!(__MODULE__, name: name, options: options)
  end

  @spec delete(t(), term()) :: boolean()
  def delete(%__MODULE__{name: name}, pattern), do: :ets.delete(name, pattern)

  @spec destroy(t()) :: boolean()
  def destroy(%__MODULE__{name: name}) do
    if Enum.member?(:ets.all(), name) do
      :ets.delete(name)
    else
      true
    end
  end

  @spec insert(t(), term()) :: boolean()
  def insert(%__MODULE__{name: name}, data), do: :ets.insert(name, data)

  @spec lookup(t(), term()) :: list(term())
  def lookup(%__MODULE__{name: name}, key), do: :ets.lookup(name, key)

  @spec match_delete(t(), term()) :: boolean()
  def match_delete(%__MODULE__{name: name}, pattern), do: :ets.match_delete(name, pattern)

  @spec match_object(t(), term()) :: list(term())
  def match_object(%__MODULE__{name: name}, spec), do: :ets.match_object(name, spec)

  @spec select_count(t(), term()) :: pos_integer()
  def select_count(%__MODULE__{name: name}, spec), do: :ets.select_count(name, spec)

  @spec from(t(), keyword()) :: {:ok, t()}
  def from(%__MODULE__{name: name} = db, file: file) do
    with true <- File.exists?(file),
         {:ok, ^name} <- :dets.open_file(name, file: file),
         true <- :ets.from_dets(name, name) do
      {:ok, db}
    end
  end

  @spec to(t(), keyword()) :: :ok
  def to(%__MODULE__{name: name}, file: file) do
    unless Enum.member?(:dets.all(), name) do
      :dets.open_file(name, ram_file: true, file: file)
    end

    with ^name <- :ets.to_dets(name, name) do
      :dets.close(name)
    end
  end
end
