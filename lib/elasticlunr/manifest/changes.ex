defmodule Elasticlunr.Manifest.Changes do
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

  @spec add_file(t(), FileMeta.t(), non_neg_integer()) :: t()
  def add_file(%__MODULE__{new_files: new_files} = changes, %FileMeta{} = file_meta, level \\ 0) do
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

  @spec decode(binary()) :: t()
  def decode(binary), do: do_decode(binary, %__MODULE__{})

  defp do_decode(<<>>, changes), do: changes

  defp do_decode(<<@k_log_number, log_number::unsigned-integer-size(64), rest::binary>>, changes) do
    do_decode(rest, %{changes | log_number: log_number})
  end

  defp do_decode(
         <<@k_next_file_number, next_file_number::unsigned-integer-size(64), rest::binary>>,
         changes
       ) do
    do_decode(rest, %{changes | next_file_number: next_file_number})
  end

  defp do_decode(
         <<@k_new_file, level::unsigned-integer, number::unsigned-integer-size(64),
           size::unsigned-integer-size(64), sk_size::unsigned-integer-size(8 * 4),
           sk::binary-size(sk_size), lk_size::unsigned-integer-size(8 * 4),
           lk::binary-size(lk_size), rest::binary>>,
         changes
       ) do
    file_meta = %FileMeta{number: number, smallest_key: sk, largest_key: lk, size: size}

    changes
    |> add_file(file_meta, level)
    |> then(&do_decode(rest, &1))
  end

  defp encode_field(:log_number, value) do
    <<@k_log_number::unsigned-integer, value::unsigned-integer-size(64)>>
  end

  defp encode_field(:next_file_number, value) do
    <<@k_next_file_number::unsigned-integer, value::unsigned-integer-size(64)>>
  end

  defp encode_field(:new_files, files) do
    Enum.map(files, fn {level, %{number: number, size: size, largest_key: lk, smallest_key: sk}} ->
      <<@k_new_file::unsigned-integer, level::unsigned-integer, number::unsigned-integer-size(64),
        size::unsigned-integer-size(64), encode_key(sk)::binary, encode_key(lk)::binary>>
    end)
  end

  defp encode_key(nil), do: <<>>

  defp encode_key(key) do
    <<byte_size(key)::unsigned-integer-size(32), key::binary>>
  end
end
