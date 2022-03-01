defmodule Elasticlunr.Scheduler.AsyncTest do
  use ExUnit.Case

  alias Elasticlunr.{Index, Scheduler}

  require Logger

  import Mox

  setup :verify_on_exit!

  setup do
    log_level = Logger.level()
    current_scheduler = Application.get_env(:elasticlunr, :scheduler)

    Logger.configure(level: :info)

    Mox.stub_with(Scheduler.Mock, Scheduler.Async)
    Application.put_env(:elasticlunr, :scheduler, Scheduler.Mock)

    on_exit(fn ->
      Logger.configure(level: log_level)
      Application.put_env(:elasticlunr, :scheduler, current_scheduler)
    end)
  end

  setup context do
    index = Index.add_field(Index.new(), "message")

    Map.put(context, :index, index)
  end

  describe "working with async scheduler" do
    test "pushes action to scheduler", %{index: index} do
      expect(Scheduler.Mock, :push, fn ^index, :calculate_idf ->
        :ok
      end)

      assert Index.add_documents(index, [%{message: "hello world"}])
    end

    test "starts a new process for index if none exists", %{index: index} do
      index = Index.add_documents(index, [%{message: "hello world"}])

      assert Scheduler.Async.started?(index)
      # sleep to allow the async scheduler process the :calculate_idf task
      Process.sleep(500)
    end

    test "handles the calculate_idf task", %{index: index} do
      expect(Scheduler.Mock, :push, fn ^index, :calculate_idf ->
        {:noreply, %{}} = Scheduler.Async.handle_cast({:calculate_idf, index}, %{})
        :ok
      end)

      index = Index.add_documents(index, [%{message: "hello world"}])

      assert [%{matched: 1, positions: %{"message" => [{0, 5}]}}] = Index.search(index, "hello")
    end
  end
end
