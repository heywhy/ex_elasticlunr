defmodule Elasticlunr.PubSub do
  use GenServer

  @spec subscribe(String.t()) :: :ok
  def subscribe(stream) do
    GenServer.call(__MODULE__, {:subscribe, stream, self()})
  end

  @spec publish(String.t(), atom(), nil | term()) :: :ok
  def publish(stream, event, args \\ nil) do
    GenServer.cast(__MODULE__, {:publish, stream, event, args})
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init([]), do: {:ok, %{}}

  @impl true
  def handle_call({:subscribe, stream, pid}, _from, state) do
    # TODO: link process so that it can be unsubscribe automatically when it shuts down.
    state
    |> Map.get(stream, MapSet.new())
    |> MapSet.put(pid)
    |> then(&Map.put(state, stream, &1))
    |> then(&{:reply, :ok, &1})
  end

  @impl true
  def handle_cast({:publish, stream, event, args}, state) do
    state
    |> Map.get(stream, MapSet.new())
    |> MapSet.to_list()
    |> Enum.each(&send(&1, {event, args}))

    {:noreply, state}
  end
end
