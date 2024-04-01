defmodule Elasticlunr.Manifest do
  alias Elasticlunr.Filename

  use Rop

  defstruct [
    :fd,
    :number,
    :log_number,
    :next_file_number,
    :new_files,
    :deleted_files,
    :versions
  ]

  @type t :: %__MODULE__{
          number: pos_integer()
        }

  @k_log_number 0
  @k_next_file_number 1

  @opts [:append, :binary]

  @spec new(pos_integer(), Path.t()) :: t()
  def new(number, dir) do
    path = Filename.manifest(dir, number)

    attrs = %{
      log_number: 0,
      next_file_number: 0,
      new_files: [],
      deleted_files: [],
      versions: [],
      number: number,
      fd: File.open!(path, @opts)
    }

    struct!(__MODULE__, attrs)
  end

  @spec new_file_number(t()) :: {pos_integer(), t()}
  def new_file_number(%__MODULE__{next_file_number: no} = manifest) do
    no
    |> Kernel.+(1)
    |> then(&{no, %{manifest | next_file_number: &1}})
  end

  @spec use_file_number(t(), pos_integer()) :: t()
  def use_file_number(%__MODULE__{next_file_number: nfn} = manifest, number) when nfn <= number do
    %{manifest | next_file_number: number + 1}
  end

  def use_file_number(%__MODULE__{} = manifest, _number), do: manifest

  @spec close(t()) :: :ok | {:error, term()}
  def close(%__MODULE__{fd: fd}) do
    case :file.sync(fd) do
      :ok -> File.close(fd)
      error -> error
    end
  end

  @spec apply_and_log(t(), map()) :: {:ok, t()} | {:error, term()}
  def apply_and_log(%__MODULE__{} = manifest, changes) do
    p = %{changes: changes, manifest: manifest}

    validate_or_set_log_number(p) >>>
      set_next_file_number() >>>
      log_changes()
  end

  defp log_changes(%{changes: changes, manifest: manifest}) do
    :ok =
      changes
      |> encode_changes()
      |> then(&IO.binwrite(manifest.fd, &1))

    {:ok, struct!(manifest, changes)}
  end

  defp encode_changes(%{} = changes) do
    Enum.reduce(changes, <<>>, fn {key, value}, acc ->
      <<acc::bits, encode(key, value)::bits>>
    end)
  end

  defp encode(:log_number, value) do
    <<@k_log_number::unsigned-integer, value::unsigned-integer-size(64)>>
  end

  defp encode(:next_file_number, value) do
    <<@k_next_file_number::unsigned-integer, value::unsigned-integer-size(64)>>
  end

  defp set_next_file_number(%{changes: changes, manifest: manifest} = params) do
    changes
    |> Map.put_new(:next_file_number, manifest.next_file_number)
    |> then(&Map.put(params, :changes, &1))
    |> then(&{:ok, &1})
  end

  defp validate_or_set_log_number(
         %{
           changes: %{log_number: number},
           manifest: %{log_number: log_number, next_file_number: next_file_number}
         } = params
       )
       when is_integer(number) do
    case number >= log_number and number < next_file_number do
      true -> {:ok, params}
      false -> {:error, "log number needs to be greater than current"}
    end
  end

  defp validate_or_set_log_number(%{changes: changes, manifest: manifest} = params) do
    changes
    |> Map.put_new(:log_number, manifest.log_number)
    |> then(&Map.put(params, :changes, &1))
    |> then(&{:ok, &1})
  end

  @spec known_files(t()) :: MapSet.t(pos_integer())
  def known_files(%__MODULE__{}) do
    MapSet.new()
  end

  @spec from_path(Path.t()) :: {:ok, t()}
  def from_path(path) do
    with {:manifest, number} <- Filename.parse(path),
         {:ok, fd} <- File.open(path, [:read, :binary]),
         %{} = changes <- extract_changes(fd),
         :ok <- File.close(fd) do
      path
      |> Path.dirname()
      |> then(&new(number, &1))
      |> then(&struct!(&1, changes))
      |> then(&{:ok, &1})
    else
      error -> error
    end
  end

  defp extract_changes(fd, acc \\ %{}) do
    with <<tag::unsigned-integer>> <- IO.binread(fd, 1),
         {key, value} <- read_tagged_change(tag, fd) do
      acc = Map.put(acc, key, value)
      extract_changes(fd, acc)
    else
      :eof -> acc
      error -> error
    end
  end

  defp read_tagged_change(tag, fd) when tag in [@k_log_number, @k_next_file_number] do
    <<value::unsigned-integer-size(64)>> = IO.binread(fd, 8)
    {tag_to_field(tag), value}
  end

  defp tag_to_field(@k_log_number), do: :log_number
  defp tag_to_field(@k_next_file_number), do: :next_file_number
end
