defmodule Elasticlunr.Storage.Blackhole do
  @moduledoc """
  As the name implies, nothing is written nowhere.
  """

  use Elasticlunr.Storage

  @impl true
  def load_all, do: []

  @impl true
  def write(_index), do: :ok

  @impl true
  def read(_name), do: {:error, "can't read index from blackhole"}

  @impl true
  def delete(_name), do: :ok
end
