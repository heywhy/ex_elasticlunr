defmodule Elasticlunr.DB do
  defstruct [:name, :options]

  @type t :: %__MODULE__{
          name: atom(),
          options: list(atom())
        }

  @spec init(atom(), list()) :: t()
  def init(name, opts \\ []) when is_atom(name) do
    if Enum.member?(:ets.all(), name) do
      :ets.delete(name)
    end

    default = ~w[compressed named_table]a
    options = Enum.uniq(default ++ opts)
    name = :ets.new(name, options)
    struct!(__MODULE__, name: name, options: options)
  end

  @spec all(t()) :: list(term())
  def all(%__MODULE__{name: name}), do: :ets.tab2list(name)

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
end
