defmodule Box.Index do
  defmacro __using__(_opts) do
    quote do
      import Box.Schema

      @before_compile Box.Index

      @spec child_spec(keyword()) :: Supervisor.child_spec()
      def child_spec(arg) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [arg]}
        }
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      alias Box.Index
      alias Box.Schema

      Module.register_attribute(__MODULE__, :schema, [])
      Module.register_attribute(__MODULE__, :compaction_strategy, [])

      fields = [:id] |> Enum.concat(Map.keys(@schema.fields)) |> Enum.uniq()

      defstruct fields

      @spec get(binary()) :: struct() | nil | no_return()
      def get(id) do
        with %{} = document <- Index.Supervisor.get(@name, id) do
          struct!(__MODULE__, document)
        end
      end

      @spec save(struct()) :: {:ok, struct()} | {:error, :not_running}
      def save(%__MODULE__{} = document) do
        with document <- Map.from_struct(document),
             {:ok, document} <- Index.Supervisor.save(@name, document) do
          {:ok, struct!(__MODULE__, document)}
        end
      end

      @spec save_all([struct()]) :: :ok | {:error, :not_running}
      def save_all([%__MODULE__{} | _rest] = documents) do
        Index.Supervisor.save_all(@name, documents)
      end

      @spec delete(binary()) :: :ok | {:error, :not_running}
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
