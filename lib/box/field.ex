defmodule Box.Field do
  @enforce_keys [:name, :type]
  defstruct [:name, :type]

  @type literal :: :uid | :date | :number | :text
  @type type :: literal() | {:array, literal()}
  @type document :: %{id: binary(), content: binary() | number() | Date.t()}

  @type t :: %__MODULE__{
          name: binary(),
          type: type()
        }

  @spec new(atom() | binary(), type()) :: t()
  def new(name, type) when is_atom(name), do: Atom.to_string(name) |> new(type)

  def new(name, type) do
    struct!(__MODULE__, name: name, type: type)
  end

  @spec add(t(), document()) :: :ok
  def add(%__MODULE__{} = _field, _documents) do
    :ok
  end

  @spec delete(t(), document()) :: t()
  def delete(%__MODULE__{} = field, _documents) do
    field
  end
end
