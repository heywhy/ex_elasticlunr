defmodule Elasticlunr.Manifest do
  alias Elasticlunr.AtomicInt
  alias Elasticlunr.Compaction
  alias Elasticlunr.FileMeta
  alias Elasticlunr.Filename
  alias Elasticlunr.Manifest.Changes
  alias Elasticlunr.Options

  use Rop

  @enforce_keys [:fd, :options]
  @fields ~w[fd options number next_file_number]a

  @enforce_keys @fields
  defstruct @fields ++
              [
                log_number: 0,
                files: %{},
                compaction_score: {-1, -1}
              ]

  @type t :: %__MODULE__{
          fd: File.io_device(),
          options: Options.t(),
          number: non_neg_integer(),
          log_number: non_neg_integer(),
          next_file_number: AtomicInt.t(),
          compaction_score: {float(), integer()},
          files: %{non_neg_integer() => [FileMeta.t()]}
        }

  @opts [:append, :binary]

  @spec new(pos_integer(), Path.t(), Options.t()) :: t()
  def new(number, dir, options \\ %Options{}) do
    path = Filename.manifest(dir, number)

    attrs = %{
      number: number,
      options: options,
      fd: File.open!(path, @opts),
      next_file_number: AtomicInt.new(0)
    }

    struct!(__MODULE__, attrs)
  end

  @spec new_file_number(t()) :: pos_integer()
  def new_file_number(%__MODULE__{} = manifest) do
    new_file_number_fn(manifest).()
  end

  @spec new_file_number_fn(t()) :: (-> pos_integer())
  def new_file_number_fn(%__MODULE__{next_file_number: ref}) do
    fn -> AtomicInt.fetch_add(ref, 1) end
  end

  @spec use_file_number(t(), pos_integer()) :: t()
  def use_file_number(%__MODULE__{next_file_number: ref} = manifest, number) do
    with value when value <= number <- AtomicInt.get(ref),
         :ok <- AtomicInt.put(ref, number + 1) do
      manifest
    else
      _ -> manifest
    end
  end

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

  @spec pick_compaction(t()) :: {:ok, Compaction.t(), t()} | {:error, term()}
  def pick_compaction(
        %__MODULE__{
          files: files,
          options: options,
          compaction_score: {_score, level}
        } = manifest
      )
      when level >= 0 do
    file_meta =
      files
      |> level_files(level)
      |> List.first()

    params = %{
      files: files,
      level: level,
      max_level: options.max_level,
      compaction: %Compaction{
        level: level,
        options: options,
        inputs: [file_meta],
        new_file_number: new_file_number_fn(manifest)
      }
    }

    ensure_level_below_max_level(params) >>>
      maybe_include_level0_overlapping_files() >>>
      include_boundary_files() >>>
      include_overlapping_files_in_parent() >>>
      include_boundary_files_in_parent() >>>
      bind((fn %{compaction: c} -> c end).()) >>>
      remove_compaction_inputs(manifest)
  end

  defp remove_compaction_inputs(compaction, %{files: files} = manifest) do
    file_nums =
      compaction.inputs
      |> Enum.concat(compaction.parent_inputs)
      |> Enum.map(& &1.number)

    updated_files = remove_deleted_files(files, file_nums)

    {:ok, compaction, %{manifest | files: updated_files}}
  end

  defp ensure_level_below_max_level(%{level: level, max_level: max_level} = params) do
    case level + 1 < max_level do
      true -> {:ok, params}
      false -> {:error, "max level reached"}
    end
  end

  defp maybe_include_level0_overlapping_files(
         %{level: 0, compaction: compaction, files: files} = params
       ) do
    {sk, lk} = key_range(compaction.inputs)

    files
    |> overlapping_files(0, sk, lk)
    |> then(&%{compaction | inputs: &1})
    |> then(&{:ok, %{params | compaction: &1}})
  end

  defp maybe_include_level0_overlapping_files(params), do: {:ok, params}

  defp include_boundary_files(%{compaction: compaction, files: files, level: level} = params) do
    files
    |> boundary_inputs(level, compaction.inputs)
    |> then(&%{compaction | inputs: &1})
    |> then(&{:ok, %{params | compaction: &1}})
  end

  defp include_overlapping_files_in_parent(
         %{compaction: compaction, files: files, level: level} = params
       ) do
    {sk, lk} = key_range(compaction.inputs)

    files
    |> overlapping_files(level + 1, sk, lk)
    |> then(&%{compaction | parent_inputs: &1})
    |> then(&{:ok, %{params | compaction: &1}})
  end

  defp include_boundary_files_in_parent(
         %{compaction: compaction, files: files, level: level} = params
       ) do
    files
    |> boundary_inputs(level + 1, compaction.parent_inputs)
    |> then(&%{compaction | parent_inputs: &1})
    |> then(&{:ok, %{params | compaction: &1}})
  end

  defp boundary_inputs(files, level, compaction_files) do
    search_fn = fn
      false, _lk, _lf, acc, _fun ->
        acc

      true, lk, files, acc, fun ->
        case find_smallest_boundary_file(files, lk) do
          nil -> fun.(false, lk, files, acc, fun)
          file_meta -> fun.(true, file_meta.largest_key, files, [file_meta | acc], fun)
        end
    end

    files = level_files(files, level)

    case find_largest_key(compaction_files) do
      nil -> compaction_files
      lk -> search_fn.(true, lk, files, compaction_files, search_fn)
    end
  end

  defp find_smallest_boundary_file(files, lk, acc \\ nil)

  defp find_smallest_boundary_file([], _lk, acc), do: acc

  defp find_smallest_boundary_file([file_meta | rest], lk, acc) do
    with true <- Cmp.gt?(file_meta.smallest_key, lk),
         true <- is_nil(acc) or Cmp.lt?(file_meta.smallest_key, acc.smallest_key) do
      find_smallest_boundary_file(rest, lk, file_meta)
    else
      false -> find_smallest_boundary_file(rest, lk, acc)
    end
  end

  defp find_largest_key([]), do: nil

  defp find_largest_key(files) do
    files
    |> Enum.map(& &1.largest_key)
    |> Cmp.max()
  end

  # credo:disable-for-next-line
  defp overlapping_files(files, level, start, stop) do
    find_fn = fn
      [], _range, _level, acc, _files, _fun ->
        acc

      [file_meta | rest], {start, stop} = range, level, acc, files, fun ->
        cond do
          start != nil and Cmp.lt?(file_meta.largest_key, start) ->
            fun.(rest, range, level, acc, files, fun)

          stop != nil and Cmp.gt?(file_meta.smallest_key, stop) ->
            fun.(rest, range, level, acc, files, fun)

          level == 0 and start != nil and Cmp.gt?(start, file_meta.smallest_key) ->
            fun.(files, {file_meta.smallest_key, stop}, level, [], files, fun)

          level == 0 and stop != nil and Cmp.lt?(stop, file_meta.largest_key) ->
            fun.(files, {start, file_meta.largest_key}, level, [], files, fun)

          true ->
            acc = [file_meta] ++ acc

            fun.(rest, range, level, acc, files, fun)
        end
    end

    files = level_files(files, level)

    find_fn.(files, {start, stop}, level, [], files, find_fn)
  end

  defp key_range(files, acc \\ {nil, nil})
  defp key_range([], acc), do: acc

  defp key_range([file_meta | rest], {nil, nil}) do
    key_range(rest, {file_meta.smallest_key, file_meta.largest_key})
  end

  defp key_range([file_meta | rest], {sk, lk}) do
    sk =
      case Cmp.lt?(file_meta.smallest_key, sk) do
        true -> file_meta.smallest_key
        false -> sk
      end

    lk =
      case Cmp.gt?(file_meta.largest_key, lk) do
        true -> file_meta.largest_key
        false -> lk
      end

    key_range(rest, {sk, lk})
  end

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
    %{changes: changes, manifest: manifest}
    |> set_next_file_number()
    |> validate_or_set_log_number() >>>
      merge_files() >>>
      compute_compaction_score()
  end

  defp level_files(files, level) do
    files
    |> Map.get(level, [])
    |> Enum.sort_by(& &1.number)
  end

  defp compute_compaction_score(%{manifest: manifest} = params) do
    score_fn = fn
      files, 0 = level, options ->
        files
        |> level_files(level)
        |> Enum.count()
        |> Kernel./(options.l0_compaction_trigger)

      files, level, options ->
        max_bytes_for_level =
          level_max_bytes(
            level,
            options.max_bytes_for_base_level,
            options.max_bytes_for_level_multiplier
          )

        files
        |> level_files(level)
        |> total_file_size()
        |> Kernel./(max_bytes_for_level)
    end

    {_, _, best_score, best_level} =
      Enum.reduce(
        0..manifest.options.max_level,
        {manifest.files, manifest.options, -1, -1},
        fn level, {files, options, best_score, _best_level} = acc ->
          score = score_fn.(files, level, options)

          case score > best_score do
            false -> acc
            true -> {files, options, score, level}
          end
        end
      )

    {:ok, %{params | manifest: %{manifest | compaction_score: {best_score, best_level}}}}
  end

  defp total_file_size(files), do: Enum.reduce(files, 0, &(&1.size + &2))

  defp level_max_bytes(level, max_size, multiplier), do: max_size * multiplier ** level

  defp merge_files(%{changes: changes, manifest: %__MODULE__{files: files} = manifest} = params) do
    %Changes{delete_files: delete_files, new_files: new_files} = changes

    files
    |> remove_deleted_files(delete_files)
    |> add_new_files(new_files)
    |> then(&%{manifest | files: &1})
    |> then(&{:ok, %{params | manifest: &1}})
  end

  defp remove_deleted_files(files, files_to_delete) do
    Enum.reduce(files, %{}, fn {level, files}, result ->
      files
      |> Enum.reject(&(&1.number in files_to_delete))
      |> then(&Map.put(result, level, &1))
    end)
  end

  defp add_new_files(files, new_files) do
    Enum.reduce(new_files, files, fn {level, file}, files ->
      files
      |> level_files(level)
      |> then(&[file | &1])
      |> then(&Map.put(files, level, &1))
    end)
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
           manifest: %{next_file_number: ref}
         } = params
       )
       when is_integer(number) do
    :ok = AtomicInt.put(ref, number)

    params
  end

  defp set_next_file_number(%{changes: changes, manifest: manifest} = params) do
    number = AtomicInt.get(manifest.next_file_number)

    changes
    |> Map.put(:next_file_number, number)
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
