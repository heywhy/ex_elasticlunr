defmodule Box.Utils do
  @spec now() :: pos_integer()
  def now, do: System.system_time(:microsecond)
end
