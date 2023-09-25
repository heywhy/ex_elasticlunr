defmodule Box.Utils do
  @spec now() :: pos_integer()
  def now, do: DateTime.to_unix(DateTime.utc_now(), :microsecond)

  @spec to_date_time(integer()) :: DateTime.t()
  def to_date_time(microseconds), do: DateTime.from_unix!(microseconds, :microsecond)
end
