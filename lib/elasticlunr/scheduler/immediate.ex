defmodule Elasticlunr.Scheduler.Immediate do
  use Elasticlunr.Scheduler

  alias Elasticlunr.{Field, Index}

  @impl true
  def push(%Index{fields: fields}, :calculate_idf) do
    fields
    |> Stream.each(fn {_, field} -> Field.calculate_idf(field) end)
    |> Stream.run()
  end
end
