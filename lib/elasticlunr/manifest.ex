defmodule Elasticlunr.Manifest do
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Filename
  alias Elasticlunr.Manifest.Changes
  alias Elasticlunr.Options

  use Rop

  @fields ~w[fd l0_compaction_trigger max_bytes_for_base_level max_bytes_for_level_multiplier max_level number]a

  @enforce_keys @fields
  defstruct @fields ++
              [
                log_number: 0,
                next_file_number: 0,
                files: %{},
                compaction_score: {-1, -1}
              ]

  @type t :: %__MODULE__{
          fd: File.io_device(),
          number: non_neg_integer(),
          max_level: non_neg_integer(),
          log_number: non_neg_integer(),
          next_file_number: non_neg_integer(),
          l0_compaction_trigger: pos_integer(),
          compaction_score: {float(), integer()},
          max_bytes_for_base_level: pos_integer(),
          max_bytes_for_level_multiplier: pos_integer(),
          files: %{non_neg_integer() => [FileMeta.t()]}
        }

  @opts [:append, :binary]

  @spec new(pos_integer(), Path.t(), Options.t()) :: t()
  def new(number, dir, options \\ %Options{}) do
    path = Filename.manifest(dir, number)

    attrs = %{
      number: number,
      fd: File.open!(path, @opts),
      max_level: options.max_level,
      l0_compaction_trigger: options.l0_compaction_trigger,
      max_bytes_for_base_level: options.max_bytes_for_base_level,
      max_bytes_for_level_multiplier: options.max_bytes_for_level_multiplier
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

  @spec current_log(t()) :: non_neg_integer()
  def current_log(%__MODULE__{log_number: number}), do: number

  @spec close(t()) :: :ok | {:error, term()}
  def close(%__MODULE__{fd: fd}) do
    with :ok <- :file.sync(fd) do
      File.close(fd)
    end
  end

  @spec apply_and_log(t(), Changes.t()) :: {:ok, t()} | {:error, term()}
  def apply_and_log(%__MODULE__{} = manifest, %Changes{} = changes) do
    do_apply(manifest, changes) >>> log_changes()
  end

  @spec needs_compaction?(t()) :: boolean()
  def needs_compaction?(%__MODULE__{compaction_score: {score, _level}}), do: score >= 1

  @spec known_files(t()) :: MapSet.t(pos_integer())
  def known_files(%__MODULE__{files: files}) do
    Enum.reduce(files, MapSet.new(), fn {_level, files}, set ->
      Enum.reduce(files, set, &MapSet.put(&2, &1.number))
    end)
  end

  @spec find_file(t(), non_neg_integer()) :: nil | FileMeta.t()
  def find_file(%__MODULE__{files: files}, number) do
    Enum.reduce_while(files, [], fn {_level, files}, acc ->
      files
      |> Enum.find(&(&1.number == number))
      |> case do
        %FileMeta{} = file_meta -> {:cont, [file_meta] ++ acc}
        nil -> {:cont, acc}
      end
    end)
    |> case do
      [] -> nil
      [file_meta] -> file_meta
    end
  end

  @spec from_path(Path.t()) :: {:ok, t()} | {:error, File.posix()}
  def from_path(path) do
    with {:manifest, number} <- Filename.parse(path),
         {:ok, fd} <- File.open(path, [:read, :binary]),
         manifest = new(number, Path.dirname(path)),
         %{} = manifest <- read_and_apply_changes(manifest, fd),
         :ok <- File.close(fd) do
      {:ok, manifest}
    end
  end

  defp do_apply(%__MODULE__{} = manifest, %Changes{} = changes) do
    set_next_file_number(%{changes: changes, manifest: manifest})
    |> validate_or_set_log_number() >>>
      merge_files() >>>
      compute_compaction_score()
  end

  defp level_files(files, level), do: Map.get(files, level, [])

  defp compute_compaction_score(%{manifest: manifest} = params) do
    score_fn = fn
      files, 0 = level ->
        files
        |> level_files(level)
        |> Enum.count()
        |> Kernel./(manifest.l0_compaction_trigger)

      files, level ->
        max_bytes_for_level =
          level_max_bytes(
            level,
            manifest.max_bytes_for_base_level,
            manifest.max_bytes_for_level_multiplier
          )

        files
        |> level_files(level)
        |> total_file_size()
        |> Kernel./(max_bytes_for_level)
    end

    {_, best_score, best_level} =
      Enum.reduce(
        0..manifest.max_level,
        {manifest.files, -1, -1},
        fn level, {files, best_score, _best_level} = acc ->
          score = score_fn.(files, level)

          case score > best_score do
            false -> acc
            true -> {files, score, level}
          end
        end
      )

    {:ok, %{params | manifest: %{manifest | compaction_score: {best_score, best_level}}}}
  end

  defp total_file_size(files), do: Enum.reduce(files, 0, &(&1.size + &2))

  defp level_max_bytes(level, max_size, multiplier), do: max_size * multiplier ** level

  defp merge_files(%{changes: changes, manifest: manifest} = params) do
    %__MODULE__{files: files} = manifest
    %Changes{new_files: new_files} = changes

    files =
      Enum.reduce(new_files, files, fn {level, file}, files ->
        files
        |> level_files(level)
        |> then(&([file] ++ &1))
        |> then(&Map.put(files, level, &1))
      end)

    {:ok, %{params | manifest: %{manifest | files: files}}}
  end

  defp log_changes(%{changes: changes, manifest: manifest}) do
    :ok =
      changes
      |> Changes.encode()
      |> then(&[IO.iodata_length(&1), &1])
      |> then(&IO.binwrite(manifest.fd, &1))

    {:ok, manifest}
  end

  defp set_next_file_number(
         %{
           changes: %{next_file_number: number},
           manifest: manifest
         } = params
       )
       when is_integer(number) do
    manifest = %{manifest | next_file_number: number}
    %{params | manifest: manifest}
  end

  defp set_next_file_number(%{changes: changes, manifest: manifest} = params) do
    changes
    |> Map.put(:next_file_number, manifest.next_file_number)
    |> then(&%{params | changes: &1})
  end

  defp validate_or_set_log_number(
         %{
           changes: %{log_number: number},
           manifest: %{log_number: log_number, next_file_number: next_file_number} = manifest
         } = params
       )
       when is_integer(number) do
    case number >= log_number and number < next_file_number do
      true ->
        %{manifest | log_number: number}
        |> then(&{:ok, %{params | manifest: &1}})

      false ->
        {:error, "log number needs to be greater than current"}
    end
  end

  defp validate_or_set_log_number(%{changes: changes, manifest: manifest} = params) do
    changes
    |> Changes.set_log_number(manifest.log_number)
    |> then(&{:ok, %{params | changes: &1}})
  end

  defp read_and_apply_changes(manifest, fd) do
    with <<size::unsigned-integer>> <- IO.binread(fd, 1),
         binary when is_binary(binary) <- IO.binread(fd, size),
         %{} = changes <- Changes.decode!(binary),
         {:ok, %{manifest: manifest}} <- do_apply(manifest, changes) do
      read_and_apply_changes(manifest, fd)
    else
      :eof -> manifest
      error -> error
    end
  end
end
