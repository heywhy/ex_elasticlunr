defmodule Elasticlunr.Fs do
  @spec stream(String.t()) :: File.Stream.t()
  def stream(path), do: File.stream!(path, [:compressed])

  @spec open(Path.t(), :append | :read | :write) :: File.io_device()
  def open(path, mode \\ :read), do: File.open!(path, [mode, :binary, :compressed])

  # coveralls-ignore-start
  @spec read(Path.t()) :: binary()
  def read(path) do
    with fd <- open(path),
         data <- IO.binread(fd, :eof),
         :ok <- File.close(fd) do
      data
    end
  end

  @spec write(Path.t(), binary()) :: :ok | no_return()
  def write(path, content), do: File.write!(path, content, [:binary, :compressed])
  # coveralls-ignore-stop

  @spec watch!(Path.t()) :: pid() | no_return()
  def watch!(dir) do
    dir
    |> via()
    |> GenServer.whereis()
    |> then(fn pid ->
      :ok = FileSystem.subscribe(pid)
      pid
    end)
  end

  @spec event_to_action([atom()]) :: :create | :remove
  def event_to_action(events) when is_list(events) do
    case :removed in events or :deleted in events do
      false -> :create
      true -> :remove
    end
  end

  @spec child_spec(Path.t()) :: Supervisor.child_spec()
  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]}
    }
  end

  @spec start_link(Path.t()) :: GenServer.on_start()
  def start_link(dir), do: FileSystem.start_link(dirs: [dir], name: via(dir))

  defp via(dir), do: {:via, Registry, {__MODULE__, dir}}
end
