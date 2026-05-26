defmodule TelegramBroadcaster.DeliveredStoreTest do
  use ExUnit.Case, async: false

  alias TelegramBroadcaster.DeliveredStore
  alias TelegramBroadcaster.TestRedis

  setup do
    start_supervised!(TestRedis)
    TestRedis.reset()
    :ok
  end

  describe "fetch/2" do
    test "returns empty map when key does not exist" do
      TestRedis.stub(["HGETALL", "telegram:delivered:order:99:bot:1"], [])

      result = DeliveredStore.fetch(1, "order:99")
      assert result == %{}
    end

    test "returns parsed map when key exists" do
      payload = Jason.encode!(%{"msg_id" => 47852, "version" => 1})

      TestRedis.stub(
        ["HGETALL", "telegram:delivered:order:99:bot:1"],
        ["111", payload]
      )

      result = DeliveredStore.fetch(1, "order:99")
      assert result["111"]["msg_id"] == 47852
    end
  end

  describe "save/5" do
    test "writes HSET with JSON payload" do
      json = Jason.encode!(%{"msg_id" => 47852, "version" => 1})

      TestRedis.stub(
        ["HSET", "telegram:delivered:order:99:bot:1", "111", json],
        1
      )

      assert DeliveredStore.save(1, "order:99", "111", 47852, 1) == :ok
    end
  end

  describe "remove/3" do
    test "deletes field from hash" do
      TestRedis.stub(
        ["HDEL", "telegram:delivered:order:99:bot:1", "111"],
        1
      )

      assert DeliveredStore.remove(1, "order:99", "111") == :ok
    end
  end
end
