defmodule Elasticlunr.Scheduler.Immediate do
  use Elasticlunr.Scheduler

  alias Elasticlunr.{Field, Index}

  @impl true
  def push(%Index{fields: fields}, :calculate_idf) do
    fields
    |> Task.async_stream(fn {_, field} -> Field.calculate_idf(field) end, ordered: false)
    |> Stream.run()
  end
end
