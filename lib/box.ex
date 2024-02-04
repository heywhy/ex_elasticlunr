# defmodule Box do
#   @moduledoc false

#   defstruct [:reference]

#   @type t :: %__MODULE__{reference: reference()}

#   @on_load :load

#   def load do
#     path = ~c"#{:code.priv_dir(:elasticlunr)}/nif"
#     :ok = :erlang.load_nif(path, 0)
#   end

#   @doc false
#   @spec init(binary()) :: reference()
#   def init(_dir), do: :erlang.nif_error(:not_loaded)

#   @spec new() :: reference()
#   def new do
#     dir =
#       :elasticlunr
#       |> Application.fetch_env!(:storage_dir)

#     # |> Path.absname()

#     # %__MODULE__{reference: init(dir)}
#     init(dir)
#   end

#   @spec set(t(), binary(), binary()) :: :ok | no_return()
#   def set(_box, _key, _value), do: :erlang.nif_error(:not_loaded)

#   @spec get(t(), binary()) :: keyword()
#   def get(_box, _key), do: :erlang.nif_error(:not_loaded)

#   @spec slim(t()) :: :ok
#   def slim(_index), do: :erlang.nif_error(:not_loaded)

#   def exec(_ref, _command), do: :erlang.nif_error(:not_loaded)

#   @spec handle(binary()) :: :ok | {:error, binary()}
#   def handle(_name), do: :erlang.nif_error(:not_loaded)

#   def call(ref) do
#     Elasticlunrexec(ref, :get_name)
#   end

#   def test do
#     b = Elasticlunrnew()
#     :ok = Elasticlunrset(b, "name", "rasheed")
#     :ok = Elasticlunrset(b, "age", 25)

#     # {:ok, v} = Elasticlunrget(b.reference, "age")
#     # s = byte_size(v)

#     # <<a::size(8)>> = v

#     # IO.inspect(a, label: "===")
#     # IO.inspect(byte_size(v), label: "===")

#     # IO.inspect("ss{#{inspect(String.trim_trailing(v))}}")
#     # raw_binary_to_string(v) |> IO.inspect()
#     # Enum.join(for <<c::utf8 <- v>>, do: <<c::utf8>>) |> IO.inspect(label: "ass")

#     # IO.puts(v)
#     # IO.puts(byte_size(v))

#     # :ok = Elasticlunrset(b.reference, "", "")
#     # {:ok, v} = Elasticlunrget(b.reference, "")

#     # v
#     # |> String.codepoints()
#     # |> tap(&IO.inspect(&1 == ""))
#     # |> IO.inspect()

#     # Elasticlunrslim(%Index{reference: nil}) |> IO.inspect(label: "as")
#     # Elasticlunrslim(%{"reference" => "nilokiasll"}) |> IO.inspect(label: "as")
#   end

#   # defp raw_binary_to_string(raw) do
#   #   codepoints = String.codepoints(raw)

#   #   val =
#   #     Enum.reduce(
#   #       codepoints,
#   #       fn w, result ->
#   #         cond do
#   #           String.valid?(w) ->
#   #             result <> w

#   #           true ->
#   #             <<parsed::8>> = w
#   #             result <> <<parsed::utf8>>
#   #         end
#   #       end
#   #     )
#   # end
# end
