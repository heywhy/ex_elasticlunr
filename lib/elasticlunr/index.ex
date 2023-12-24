defmodule Elasticlunr.Index do
  defmacro __using__(_opts) do
    quote do
      alias Elasticlunr.Compaction

      import Elasticlunr.Schema

      @before_compile Elasticlunr.Index

      @spec child_spec(keyword()) :: Supervisor.child_spec()
      def child_spec(arg) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [arg]}
        }
      end
    end
  end

  # credo:disable-for-next-line
  defmacro __before_compile__(_env) do
    quote do
      alias Elasticlunr.Index
      alias Elasticlunr.Schema

      fields = [:id] |> Enum.concat(Map.keys(@schema.fields)) |> Enum.uniq()

      defstruct fields

      @spec get(binary()) :: struct() | nil
      def get(id) do
        with %{} = document <- Index.Supervisor.get(@name, id) do
          struct!(__MODULE__, document)
        end
      end

      @spec save(struct()) :: struct()
      def save(%__MODULE__{} = document) do
        with document <- Map.from_struct(document),
             document <- Index.Supervisor.save(@name, document) do
          struct!(__MODULE__, document)
        end
      end

      @spec save_all([struct()]) :: :ok
      def save_all([%__MODULE__{} | _rest] = documents) do
        Index.Supervisor.save_all(@name, documents)
      end

      @spec delete(binary()) :: :ok
      def delete(id), do: Index.Supervisor.delete(@name, id)

      @spec __schema__() :: Schema.t()
      if @compaction_strategy do
        def __schema__ do
          struct!(@schema, compaction_strategy: @compaction_strategy)
        end
      else
        def __schema__, do: @schema
      end

      @spec running?() :: boolean()
      def running?, do: Index.Supervisor.running?(@name)

      @spec start_link(keyword()) :: GenServer.on_start()
      def start_link(_opts), do: Index.Supervisor.start_link(schema: __schema__())
    end
  end
end
