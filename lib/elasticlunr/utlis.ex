defmodule Elasticlunr.Utils do
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
