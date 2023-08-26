defmodule Box.Field do
  @enforce_keys [:type]
  defstruct [:type]

  @type literal :: :uid | :date | :number | :text
  @type type :: literal() | {:array, literal()}
  @type document :: %{id: binary(), content: binary() | number() | Date.t()}

  @type t :: %__MODULE__{type: type()}

  @spec add(t(), document()) :: :ok
  def add(%__MODULE__{} = _field, _documents) do
    :ok
  end

  @spec delete(t(), document()) :: t()
  def delete(%__MODULE__{} = field, _documents) do
    field
  end
end
