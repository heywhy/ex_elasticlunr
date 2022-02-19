defmodule Elasticlunr.Dyno do
  use GenServer

  alias Elasticlunr.{DB, Field, Index, IndexRegistry, IndexSupervisor, Operation}
  alias Elasticlunr.Utils.Process

  @spec get(String.t()) :: Index.t()
  def get(name) do
    GenServer.call(via(name), :get)
  end

  @spec update(Index.t()) :: {:ok, Index.t()} | {:error, any()}
  def update(%Index{name: name} = index) do
    :ok = GenServer.cast(via(name), {:update, index})
    {:ok, %{index | ops: []}}
  end

  @spec running :: [binary()]
  def running do
    Process.active_processes(IndexSupervisor, IndexRegistry, __MODULE__)
  end

  @spec start(Index.t()) :: {:ok, pid()} | {:error, any()}
  def start(index) do
    # credo:disable-for-next-line
    with {:ok, _} <- DynamicSupervisor.start_child(IndexSupervisor, {__MODULE__, index}),
         {:ok, index} <- update(index) do
      {:ok, index}
    end
  end

  @spec stop(Index.t()) :: :ok | {:error, :not_found}
  def stop(%Index{name: name}) do
    with [{pid, _}] <- Registry.lookup(IndexRegistry, name),
         :ok <- DynamicSupervisor.terminate_child(IndexSupervisor, pid) do
      :ok
    else
      [] ->
        {:error, :not_found}

      err ->
        err
    end
  end

  @spec init(String.t()) :: {:ok, map()}
  def init(name) do
    name = String.to_atom("elasticlunr_#{name}")

    {:ok, %{index: nil, db: DB.init(name, ~w[set public]a)}}
  end

  def start_link(name) do
    GenServer.start_link(__MODULE__, name, name: via(name), hibernate_after: 5_000)
  end

  @spec child_spec(Index.t()) :: map()
  def child_spec(%Index{name: id}) do
    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [id]},
      restart: :transient
    }
  end

  @spec via(binary()) :: {:via, Registry, {IndexRegistry, atom()}}
  def via(name) do
    {:via, Registry, {IndexRegistry, name}}
  end

  def handle_call(:get, _from, state) do
    {:reply, state[:index], state}
  end

  def handle_cast({:update, index}, state) do
    index = apply_operations(index, state)
    {:noreply, %{state | index: index}}
  end

  defp apply_operations(%{ops: ops} = index, state) do
    index = Enum.reduce(ops, index, &apply_operation(&2, &1, state))
    update_documents_size(%{index | ops: []}, state)
  end

  defp apply_operation(
         index,
         %Operation{type: :initialize, params: params},
         state
       ) do
    opts = Keyword.take(params, ~w[name pipeline ref store_documents store_positions]a)
    true = DB.insert(state.db, {:options, opts})

    Enum.reduce(params[:fields], index, fn {name, opts}, index ->
      op = Operation.new(:add_field, [name: name] ++ opts)
      apply_operation(index, op, state)
    end)
  end

  defp apply_operation(index, %Operation{type: :add_field, params: params}, state) do
    opts = Keyword.take(params, ~w[name pipeline store_documents store_positions]a)
    true = DB.insert(state.db, {{:field, params[:name]}, opts ++ [db: state.db]})
    index
  end

  defp apply_operation(index, %{type: :add_documents, params: documents}, state) do
    fields = get_fields(state)
    index_opts = get_index_opts(state)

    :ok =
      documents
      |> Flow.from_enumerable()
      |> Flow.map(fn document ->
        document = flatten_document(document)
        add_document(index_opts[:ref], fields, document)
      end)
      |> Flow.partition()
      |> Flow.run()

    index
  end

  defp add_document(ref, fields, document) do
    Enum.each(Map.keys(document), fn attribute ->
      if Map.has_key?(fields, attribute) do
        opts = Map.get(fields, attribute)

        data = [
          %{id: document[ref], content: document[attribute]}
        ]

        Field.add(Field.new(opts), data)
      end
    end)
  end

  defp get_fields(state) do
    DB.match_object(state.db, {{:field, :_}, :_})
    |> Enum.map(fn {{:field, key}, opts} -> {key, opts} end)
    |> Enum.into(%{})
  end

  defp get_index_opts(state) do
    [{:options, opts}] = DB.lookup(state.db, :options)
    opts
  end

  defp update_documents_size(index, state) do
    fields = get_fields(state)

    size =
      Enum.reduce(fields, 0, fn {_, opts}, acc ->
        size = Field.length(Field.new(opts), :ids)

        if size > acc do
          size
        else
          acc
        end
      end)

    %{index | documents_size: size}
  end

  defp flatten_document(document, prefix \\ "") do
    Enum.reduce(document, %{}, fn
      {key, value}, transformed when is_map(value) ->
        mapped = flatten_document(value, "#{prefix}#{key}.")
        Map.merge(transformed, mapped)

      {key, value}, transformed ->
        Map.put(transformed, "#{prefix}#{key}", value)
    end)
  end
end
