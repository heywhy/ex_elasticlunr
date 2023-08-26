defmodule Box.Writer do
  use GenServer

  alias __MODULE__.Supervisor

  defstruct [:dir]

  @type t :: %__MODULE__{dir: Path.t()}

  @spec running?(struct()) :: boolean()
  def running?(%_{schema: _, dir: _} = index) do
    Supervisor.running?(index)
  end

  @spec start(struct()) :: :ok
  def start(index), do: Supervisor.start_child(index)

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
end
