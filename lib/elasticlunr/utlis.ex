defmodule Elasticlunr.Utils do
  @spec new_id() :: binary()
  def new_id, do: FlakeIdWorker.get()

  @spec id_to_string(binary()) :: String.t()
  def id_to_string(id), do: FlakeId.to_string(id)

  @spec id_from_string(String.t()) :: binary()
  def id_from_string(string), do: FlakeId.from_string(string)

  @spec now() :: pos_integer()
  def now, do: DateTime.to_unix(DateTime.utc_now(), :microsecond)

  @spec to_date_time(integer()) :: DateTime.t()
  def to_date_time(microseconds), do: DateTime.from_unix!(microseconds, :microsecond)

  @spec levenshtein_distance(binary, binary) :: integer()
  def levenshtein_distance(a, b) do
    ta = String.downcase(a) |> to_charlist |> List.to_tuple()
    tb = String.downcase(b) |> to_charlist |> List.to_tuple()
    m = tuple_size(ta)
    n = tuple_size(tb)
    costs = Enum.reduce(0..m, %{}, fn i, acc -> Map.put(acc, {i, 0}, i) end)
    costs = Enum.reduce(0..n, costs, fn j, acc -> Map.put(acc, {0, j}, j) end)

    Enum.reduce(0..(n - 1), costs, fn j, acc ->
      Enum.reduce(0..(m - 1), acc, fn i, map ->
        # credo:disable-for-lines:2
        d =
          if elem(ta, i) == elem(tb, j) do
            map[{i, j}]
          else
            # deletion
            Enum.min([
              map[{i, j + 1}] + 1,
              # insertion
              map[{i + 1, j}] + 1,
              # substitution
              map[{i, j}] + 1
            ])
          end

        Map.put(map, {i + 1, j + 1}, d)
      end)
    end)
    |> Map.get({m, n})
  end
end
