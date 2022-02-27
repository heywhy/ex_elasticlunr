defmodule Elasticlunr.Logger do
  require Logger

  @spec debug(binary() | iodata(), keyword()) :: :ok
  def debug(msg, opts \\ []) do
    Logger.debug("[elasticlunr] #{msg}", opts)
  end

  @spec error(binary() | iodata(), keyword()) :: :ok
  def error(msg, opts \\ []) do
    Logger.error("[elasticlunr] #{msg}", opts)
  end
end
