defmodule Elasticlunr.Encoding do
  @spec put_boolean(iodata(), boolean()) :: iodata()
  def put_boolean(data, bool) when is_list(data) and is_boolean(bool) do
    case bool do
      true -> data ++ [<<1>>]
      false -> data ++ [<<0>>]
    end
  end

  @spec put_float(iodata(), float()) :: iodata()
  def put_float(data, number) when is_list(data) do
    data ++ [<<number::float>>]
  end

  @spec put_float64(iodata(), float()) :: iodata()
  def put_float64(data, number) when is_list(data) and is_float(number) do
    data ++ [<<number::float-size(8)-unit(8)>>]
  end

  @spec put_int(iodata(), integer()) :: iodata()
  def put_int(data, number) when is_list(data) do
    data ++ [number]
  end

  @spec put_int32(iodata(), integer()) :: iodata()
  def put_int32(data, number) when is_list(data) and is_integer(number) do
    data ++ [<<number::integer-size(4)-unit(8)>>]
  end

  @spec put_int64(iodata(), integer()) :: iodata()
  def put_int64(data, number) when is_list(data) and is_integer(number) do
    data ++ [<<number::integer-size(8)-unit(8)>>]
  end

  @type size :: :big | :tiny

  @spec put_size_prefixed(iodata(), iodata(), size()) :: iodata()
  def put_size_prefixed(data, binary, size \\ :big)

  def put_size_prefixed(data, content, :big) when is_list(data) do
    size = IO.iodata_length(content)

    data
    |> put_int64(size)
    |> then(&(&1 ++ [content]))
  end

  def put_size_prefixed(data, content, :tiny) when is_list(data) do
    size = IO.iodata_length(content)

    data
    |> put_int(size)
    |> then(&(&1 ++ [content]))
  end

  @spec get_boolean!(binary() | IO.device()) :: boolean() | IO.nodata() | no_return()
  def get_boolean!(<<1>>), do: true
  def get_boolean!(<<0>>), do: false

  def get_boolean!(device) when is_pid(device) do
    device
    |> IO.binread(1)
    |> get_boolean!()
  end

  @spec get_int!(IO.device()) :: integer()
  def get_int!(device) when is_pid(device) do
    device
    |> IO.binread(1)
    |> then(&(<<_::unsigned-integer>> = &1))
    |> then(&:binary.decode_unsigned/1)
  end

  @spec get_int64!(binary() | IO.device()) :: integer() | IO.nodata() | no_return()
  def get_int64!(<<number::integer-size(8)-unit(8)>>), do: number

  def get_int64!(device) when is_pid(device) do
    device
    |> IO.binread(8)
    |> get_int64!()
  end

  @spec get_size_prefixed!(IO.device()) :: binary() | no_return()
  def get_size_prefixed!(device) when is_pid(device) do
    device
    |> get_int64!()
    |> then(&IO.binread(device, &1))
    |> then(&(<<_::binary>> = &1))
  end

  @spec chop_boolean!(binary()) :: {boolean(), binary()} | no_return()
  def chop_boolean!(<<1, binary::binary>>), do: {true, binary}
  def chop_boolean!(<<0, binary::binary>>), do: {false, binary}

  @spec chop_float!(binary()) :: {float(), binary()} | no_return()
  def chop_float!(<<number::float, rest::binary>>), do: {number, rest}

  @spec chop_float64!(binary()) :: {float(), binary()} | no_return()
  def chop_float64!(<<number::float-size(8)-unit(8), rest::binary>>) do
    {number, rest}
  end

  @spec chop_int!(binary()) :: {integer(), binary()} | no_return()
  def chop_int!(<<number::integer-size(1)-unit(8), rest::binary>>) do
    {number, rest}
  end

  @spec chop_int32!(binary()) :: {integer(), binary()} | no_return()
  def chop_int32!(<<number::integer-size(4)-unit(8), rest::binary>>) do
    {number, rest}
  end

  @spec chop_int64!(binary()) :: {integer(), binary()} | no_return()
  def chop_int64!(<<number::integer-size(8)-unit(8), rest::binary>>) do
    {number, rest}
  end

  @spec chop_size_prefixed!(binary(), size()) :: {binary(), binary()} | no_return()
  def chop_size_prefixed!(binary, size \\ :big)

  def chop_size_prefixed!(binary, :big) do
    {size, binary} = chop_int64!(binary)
    <<value::binary-size(size), binary::binary>> = binary

    {value, binary}
  end

  def chop_size_prefixed!(binary, :tiny) do
    {size, binary} = chop_int!(binary)
    <<value::binary-size(size), binary::binary>> = binary

    {value, binary}
  end
end
