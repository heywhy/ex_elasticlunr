defmodule Box.Fs do
  @spec stream(String.t()) :: File.Stream.t()
  def stream(path), do: File.stream!(path, [:compressed])

  @spec open(Path.t(), :append | :read | :write) :: File.io_device()
  def open(path, mode \\ :read), do: File.open!(path, [mode, :binary, :compressed])

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

  @spec child_spec(Path.t()) :: Supervisor.child_spec()
  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]}
    }
  end

  @spec start_link(Path.t()) :: GenServer.on_start()
  if Application.compile_env(:elasticlunr, :env) == :test do
    def start_link(dir) do
      opts = [
        dirs: [dir],
        interval: 10,
        name: via(dir),
        backend: :fs_poll
      ]

      FileSystem.start_link(opts)
    end
  else
    def start_link(dir), do: FileSystem.start_link(dirs: [dir], name: via(dir))
  end

  defp via(dir), do: {:via, Registry, {__MODULE__, dir}}
end
