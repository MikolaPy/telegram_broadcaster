defmodule TelegramBroadcaster.DispatchStoreTest do
  use ExUnit.Case, async: false

  alias TelegramBroadcaster.DispatchStore
  alias TelegramBroadcaster.TestRedis

  setup do
    start_supervised!(TestRedis)
    TestRedis.reset()
    :ok
  end

  describe "fetch/2" do
    test "returns empty map when key does not exist" do
      TestRedis.stub(["HGETALL", "telegram:dispatch:order:99:bot:1"], [])

      result = DispatchStore.fetch(1, "order:99")
      assert result == %{}
    end

    test "returns parsed map when key exists" do
      payload = Jason.encode!(%{"text" => "Hello", "version" => 1, "reply_markup" => %{}})

      TestRedis.stub(
        ["HGETALL", "telegram:dispatch:order:99:bot:1"],
        ["111", payload, "222", payload]
      )

      result = DispatchStore.fetch(1, "order:99")

      assert Map.keys(result) |> Enum.sort() == ["111", "222"]
      assert result["111"]["version"] == 1
    end
  end
end
