defmodule Elasticlunr.Scheduler.Provider do
  @moduledoc false

  alias Elasticlunr.Index

  @callback push(index :: Index.t(), action :: atom()) :: :ok
end
