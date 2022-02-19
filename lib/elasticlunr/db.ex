defmodule Elasticlunr.DB do
  defstruct [:name]

  @type t :: %__MODULE__{
          name: atom()
        }

  @spec init(atom(), list()) :: t()
  def init(name, opts \\ []) when is_atom(name) do
    default = ~w[compressed named_table]a
    name = :ets.new(name, Enum.uniq(default ++ opts))
    struct!(__MODULE__, name: name)
  end

  @spec all(t()) :: list(term())
  def all(%__MODULE__{name: name}), do: :ets.tab2list(name)

  @spec insert(t(), term()) :: boolean()
  def insert(%__MODULE__{name: name}, data), do: :ets.insert(name, data)

  @spec lookup(t(), term()) :: list(term())
  def lookup(%__MODULE__{name: name}, key), do: :ets.lookup(name, key)

  @spec match_object(t(), term()) :: list(term())
  def match_object(%__MODULE__{name: name}, spec), do: :ets.match_object(name, spec)

  @spec select_count(t(), term()) :: pos_integer()
  def select_count(%__MODULE__{name: name}, spec), do: :ets.select_count(name, spec)
end
