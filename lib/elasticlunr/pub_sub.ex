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
    ref = Process.monitor(pid)

    state
    |> Map.get(stream, MapSet.new())
    |> MapSet.put({pid, ref})
    |> then(&Map.put(state, stream, &1))
    |> then(&{:reply, :ok, &1})
  end

  @impl true
  def handle_cast({:publish, stream, event, args}, state) do
    state
    |> Map.get(stream, MapSet.new())
    |> Enum.map(&elem(&1, 0))
    |> Enum.each(&send(&1, {event, args}))

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    state =
      Enum.reduce(state, state, fn {stream, pids}, state ->
        pids
        |> MapSet.symmetric_difference(MapSet.new([{pid, ref}]))
        |> then(&%{state | stream => &1})
      end)

    {:noreply, state}
  end
end
