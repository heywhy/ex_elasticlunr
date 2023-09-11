defmodule Box.Index.Fs do
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
        backend: :fs_poll,
        name: {:via, Registry, {__MODULE__, dir}}
      ]

      FileSystem.start_link(opts)
    end
  else
    def start_link(dir) do
      opts = [dirs: [dir], name: {:via, Registry, {__MODULE__, dir}}]

      FileSystem.start_link(opts)
    end
  end
end
