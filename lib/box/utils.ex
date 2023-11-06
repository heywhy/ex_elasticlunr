defmodule Box.Utils do
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
end
