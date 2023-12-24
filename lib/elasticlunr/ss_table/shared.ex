defmodule Elasticlunr.SSTable.Shared do
  @moduledoc false

  @spec segment_file(Path.t()) :: Path.t()
  def segment_file(dir), do: Path.join(dir, "data.db")
end
