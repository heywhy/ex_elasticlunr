defmodule Elasticlunr.Storage.Provider do
  @moduledoc false

  alias Elasticlunr.Index

  @callback load_all() :: Enum.t()
  @callback read(name :: binary()) :: Index.t() | {:error, any()}
  @callback delete(name :: binary()) :: :ok | {:error, any()}
  @callback write(index :: Index.t()) :: :ok | {:error, any()}
end
