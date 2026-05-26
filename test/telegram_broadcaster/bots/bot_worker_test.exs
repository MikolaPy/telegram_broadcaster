defmodule TelegramBroadcaster.BotWorkerTest do
  use ExUnit.Case, async: false

  alias TelegramBroadcaster.BotWorker
  alias TelegramBroadcaster.TestRedis

  setup do
    start_supervised!(TestRedis)
    TestRedis.reset()

    {:ok, pid} =
      BotWorker.start_link(bot_id: 1, bot_token: "test_token", tick_interval_ms: 100_000)

    {:ok, pid: pid}
  end

  describe "trigger_sync/2" do
    test "processes new dispatch — adds to insert_queue" do
      payload = Jason.encode!(%{"text" => "Hello", "version" => 1, "reply_markup" => %{}})

      TestRedis.stub(
        ["HGETALL", "telegram:dispatch:order:99:bot:1"],
        ["111", payload, "222", payload]
      )

      TestRedis.stub(["HGETALL", "telegram:delivered:order:99:bot:1"], [])

      :ok = BotWorker.trigger_sync(1, "order:99")

      # Give the GenServer time to process the cast
      Process.sleep(50)

      state = BotWorker.get_state(1)
      assert length(state["order:99"].insert_queue) == 2
      assert state["order:99"].delete_queue == []
    end

    test "processes cancel — adds to delete_queue" do
      delivered =
        Jason.encode!(%{"msg_id" => 47852, "version" => 1})

      TestRedis.stub(["HGETALL", "telegram:dispatch:order:99:bot:1"], [])
      TestRedis.stub(["HGETALL", "telegram:delivered:order:99:bot:1"], ["111", delivered])

      :ok = BotWorker.trigger_sync(1, "order:99")

      Process.sleep(50)

      state = BotWorker.get_state(1)
      assert state["order:99"].insert_queue == []
      assert length(state["order:99"].delete_queue) == 1
    end

    test "idempotent — no tracking entry when desired matches delivered" do
      payload = Jason.encode!(%{"text" => "Hello", "version" => 1, "reply_markup" => %{}})
      delivered = Jason.encode!(%{"msg_id" => 47852, "version" => 1})

      TestRedis.stub(
        ["HGETALL", "telegram:dispatch:order:99:bot:1"],
        ["111", payload]
      )

      TestRedis.stub(["HGETALL", "telegram:delivered:order:99:bot:1"], ["111", delivered])

      :ok = BotWorker.trigger_sync(1, "order:99")

      Process.sleep(50)

      state = BotWorker.get_state(1)
      # No entry = nothing to do = idempotent
      assert Map.has_key?(state, "order:99") == false
    end
  end
end
