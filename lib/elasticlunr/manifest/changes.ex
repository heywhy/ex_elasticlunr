defmodule Elasticlunr.Manifest.Changes do
  alias Elasticlunr.Encoding
  alias Elasticlunr.FileMeta

  defstruct [:log_number, :next_file_number, new_files: []]

  @type t :: %__MODULE__{
          log_number: nil | pos_integer(),
          next_file_number: nil | pos_integer(),
          new_files: [{pos_integer(), FileMeta.t()}]
        }

  @k_log_number 0
  @k_next_file_number 1
  @k_new_file 2

  @spec set_log_number(pos_integer()) :: t()
  def set_log_number(number) do
    set_log_number(%__MODULE__{}, number)
  end

  @spec set_log_number(t(), pos_integer()) :: t()
  def set_log_number(%__MODULE__{} = changes, number), do: %{changes | log_number: number}

  @spec set_next_file_number(pos_integer()) :: t()
  def set_next_file_number(number) do
    set_next_file_number(%__MODULE__{}, number)
  end

  @spec set_next_file_number(t(), pos_integer()) :: t()
  def set_next_file_number(%__MODULE__{} = changes, number) do
    %{changes | next_file_number: number}
  end

  @spec add_file(t(), non_neg_integer(), FileMeta.t()) :: t()
  def add_file(%__MODULE__{new_files: new_files} = changes, level, %FileMeta{} = file_meta) do
    %{changes | new_files: [{level, file_meta}] ++ new_files}
  end

  @spec encode(t()) :: iodata()
  def encode(%__MODULE__{} = changes) do
    keys = [:log_number, :next_file_number, :new_files]

    changes
    |> Map.from_struct()
    |> then(&Enum.map(keys, fn key -> {key, &1[key]} end))
    |> Enum.reject(fn {_, v} -> v == nil or v == [] end)
    |> Enum.map(fn {key, value} -> encode_field(key, value) end)
  end

  @spec decode!(binary()) :: t() | no_return()
  def decode!(binary), do: decode!(binary, %__MODULE__{})

  defp decode!(<<>>, changes), do: changes

  defp decode!(binary, changes) do
    {tag, binary} = Encoding.chop_int!(binary)

    case tag do
      @k_log_number ->
        {log_number, binary} = Encoding.chop_int64!(binary)
        decode!(binary, %{changes | log_number: log_number})

      @k_next_file_number ->
        {next_file_number, binary} = Encoding.chop_int64!(binary)
        decode!(binary, %{changes | next_file_number: next_file_number})

      @k_new_file ->
        {level, binary} = Encoding.chop_int!(binary)
        {number, binary} = Encoding.chop_int64!(binary)
        {size, binary} = Encoding.chop_int64!(binary)
        {sk, binary} = Encoding.chop_size_prefixed!(binary)
        {lk, binary} = Encoding.chop_size_prefixed!(binary)

        file_meta = %FileMeta{number: number, smallest_key: sk, largest_key: lk, size: size}

        changes
        |> add_file(level, file_meta)
        |> then(&decode!(binary, &1))
    end
  end

  defp encode_field(:log_number, value) do
    []
    |> Encoding.put_int(@k_log_number)
    |> Encoding.put_int64(value)
  end

  defp encode_field(:next_file_number, value) do
    []
    |> Encoding.put_int(@k_next_file_number)
    |> Encoding.put_int64(value)
  end

  defp encode_field(:new_files, files) do
    Enum.map(files, fn {level, %{number: number, size: size, largest_key: lk, smallest_key: sk}} ->
      []
      |> Encoding.put_int(@k_new_file)
      |> Encoding.put_int(level)
      |> Encoding.put_int64(number)
      |> Encoding.put_int64(size)
      |> Encoding.put_size_prefixed(sk)
      |> Encoding.put_size_prefixed(lk)
    end)
  end
end
