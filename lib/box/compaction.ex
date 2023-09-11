defmodule Box.Compaction do
  use GenServer

  alias Box.Schema

  require Logger

  defstruct [:dir, :schema]

  @type t :: %__MODULE__{
          dir: Path.t(),
          schema: Schema.t()
        }

  @lockfile "c.lock"

  @spec unfinished?(Path.t()) :: boolean()
  def unfinished?(dir) do
    dir
    |> Path.join(@lockfile)
    |> File.exists?()
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, hibernate_after: 5_000)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    dir = Keyword.fetch!(opts, :dir)
    schema = Keyword.fetch!(opts, :schema)

    {:ok, struct!(__MODULE__, dir: dir, schema: schema)}
  end

  @impl true
  def terminate(reason, %__MODULE__{schema: schema}) do
    Logger.debug("Terminating compaction process for #{schema.name} due to #{inspect(reason)}")
  end
end
