defmodule Elasticlunr.Test.Fixture do
  @moduledoc false

  @spec stemmer_fixture() :: map()
  def stemmer_fixture do
    with path <- Path.join(__DIR__, "./stemmer_fixture.json"),
         {:ok, content} <- File.read(path),
         {:ok, map} <- Jason.decode(content) do
      map
    end
  end
end
