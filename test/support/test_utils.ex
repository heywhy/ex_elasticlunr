defmodule Elasticlunr.TestUtils do
  alias Elasticlunr.Filename
  alias Elasticlunr.Fs

  @spec ss_tables(Path.t()) :: [non_neg_integer()]
  def ss_tables(dir) do
    dir
    |> Fs.db_files()
    |> Enum.map(&Filename.parse/1)
    |> Enum.filter(&match?({:sst, _number}, &1))
    |> Enum.map(&elem(&1, 1))
  end
end
