defmodule Elasticlunr.Scheduler do
  @moduledoc false

  alias Elasticlunr.Index

  @callback push(index :: Index.t(), action :: atom()) :: :ok

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Elasticlunr.Scheduler
    end
  end
end
