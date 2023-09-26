defmodule Box.Compaction.SizeTiered do
  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, hibernate_after: 5_000)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {:ok, opts}
  end
end
