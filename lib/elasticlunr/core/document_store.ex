defmodule Elasticlunr.DocumentStore do
  @moduledoc false

  alias Elasticlunr.Index

  defstruct save: true, documents: %{}, document_info: %{}, length: 0

  @type t :: %__MODULE__{
          save: boolean(),
          documents: map(),
          document_info: map(),
          length: pos_integer()
        }

  @spec new(boolean()) :: t()
  def new(save \\ true) do
    struct!(%__MODULE__{}, %{save: save})
  end

  @spec add(t(), Index.document_ref(), map()) :: t()
  def add(%__MODULE__{documents: documents, length: length, save: save} = store, ref, document) do
    length =
      case exists?(store, ref) do
        true ->
          length

        false ->
          length + 1
      end

    documents =
      case save do
        true ->
          Map.put(documents, ref, document)

        false ->
          Map.put(documents, ref, nil)
      end

    %{store | length: length, documents: documents}
  end

  @spec get(t(), Index.document_ref()) :: map() | nil
  def get(%__MODULE__{documents: documents}, ref), do: Map.get(documents, ref)

  @spec remove(t(), Index.document_ref()) :: map() | nil
  def remove(
        %__MODULE__{document_info: document_info, documents: documents, length: length} = store,
        ref
      ) do
    case exists?(store, ref) do
      true ->
        length = length - 1
        documents = Map.delete(documents, ref)
        document_info = Map.delete(document_info, ref)

        %{store | document_info: document_info, documents: documents, length: length}

      false ->
        store
    end
  end

  @spec exists?(t(), Index.document_ref()) :: boolean()
  def exists?(%__MODULE__{documents: documents}, ref), do: Map.has_key?(documents, ref)

  @spec add_field_length(t(), Index.document_ref(), Index.document_field(), pos_integer()) :: t()
  def add_field_length(%__MODULE__{document_info: document_info} = store, ref, field, length) do
    case exists?(store, ref) do
      false ->
        store

      true ->
        info =
          document_info
          |> Map.get(ref, %{})
          |> Map.put(field, length)

        document_info = Map.put(document_info, ref, info)
        %{store | document_info: document_info}
    end
  end

  @spec update_field_length(t(), Index.document_ref(), Index.document_field(), pos_integer()) ::
          t()
  def update_field_length(%__MODULE__{} = store, ref, field, length),
    do: add_field_length(store, ref, field, length)

  @spec get_field_length(t(), Index.document_ref(), Index.document_field()) :: pos_integer()
  def get_field_length(%__MODULE__{document_info: document_info} = store, ref, field) do
    case exists?(store, ref) do
      false ->
        nil

      true ->
        document_info
        |> Map.get(ref, %{})
        |> Map.get(field)
    end
  end

  @spec reset(t(), boolean()) :: t()
  def reset(%__MODULE__{}, save \\ true), do: new(save)
end
