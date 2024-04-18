defmodule Elasticlunr.Fs do
  @type mode :: :read | :write

  @spec stream(String.t()) :: File.Stream.t()
  def stream(path), do: File.stream!(path, [:compressed])

  @spec open(Path.t(), mode()) ::
          {:ok, File.io_device()} | {:error, File.posix()}
  def open(path, mode \\ :read), do: File.open(path, [mode, :binary, :compressed])

  @spec open!(Path.t(), mode()) :: File.io_device() | no_return()
  def open!(path, mode \\ :read) do
    {:ok, fd} = open(path, mode)
    fd
  end

  @spec db_files(Path.t()) :: [Path.t()]
  def db_files(path) do
    path
    |> Path.join("*")
    |> Path.wildcard()
  end

  # coveralls-ignore-start
  @spec read(Path.t()) :: binary()
  def read(path) do
    with {:ok, fd} <- open(path),
         data <- IO.binread(fd, :eof),
         :ok <- File.close(fd) do
      data
    end
  end

  @spec write(Path.t(), binary()) :: :ok | no_return()
  def write(path, content), do: File.write!(path, content, [:binary, :compressed])
  # coveralls-ignore-stop
end
