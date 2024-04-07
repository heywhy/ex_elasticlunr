defmodule Elasticlunr.Filename do
  @type file_type :: :current | :manifest | :log | :sst | :tmp

  @spec current(Path.t()) :: String.t()
  def current(path), do: "#{path}/CURRENT"

  @spec manifest(Path.t(), pos_integer()) :: String.t()
  def manifest(path, number) when is_integer(number) and number > 0 do
    number
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
    |> then(&"#{path}/MANIFEST-#{&1}")
  end

  @spec temp(Path.t(), pos_integer()) :: String.t()
  def temp(path, number) when is_integer(number) and number > 0 do
    filename(path, number, "tmp")
  end

  @spec ss_table(Path.t(), pos_integer()) :: String.t()
  def ss_table(path, number) do
    filename(path, number, "sst")
  end

  @spec log(Path.t(), pos_integer()) :: String.t()
  def log(path, number) do
    # TODO: change suffix to `log`
    filename(path, number, "wal")
  end

  @spec parse(Path.t()) :: {file_type(), integer()}
  def parse(path) do
    from_extension = fn file ->
      case String.split(file, ".") do
        [number, "sst"] -> {:sst, String.to_integer(number)}
        [number, "tmp"] -> {:tmp, String.to_integer(number)}
        [number, "wal"] -> {:log, String.to_integer(number)}
      end
    end

    case Path.basename(path) do
      "CURRENT" -> {:current, 0}
      "MANIFEST-" <> number -> {:manifest, String.to_integer(number)}
      file -> from_extension.(file)
    end
  end

  defp filename(path, number, suffix) do
    number
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
    |> then(&"#{path}/#{&1}.#{suffix}")
  end
end
