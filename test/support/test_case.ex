defmodule Elasticlunr.TestCase do
  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case

      alias Elasticlunr.{Dyno, Index, IndexManager}

      setup do
        on_exit(fn ->
          Enum.each(Dyno.running(), fn dyno ->
            IndexManager.remove(%Index{name: dyno})
          end)
        end)
      end
    end
  end
end
