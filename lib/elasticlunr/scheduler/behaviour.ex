defmodule Elasticlunr.Scheduler.Behaviour do
  @moduledoc false

  alias Elasticlunr.Index

  @callback push(index :: Index.t(), action :: atom()) :: :ok
end
