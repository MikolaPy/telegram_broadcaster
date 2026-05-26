defmodule TelegramBroadcaster.DispatcherTest do
  use ExUnit.Case, async: true

  alias TelegramBroadcaster.Dispatcher

  describe "handle_sync_signal/1" do
    test "parses valid JSON and returns tracking_id and bot_ids" do
      json = Jason.encode!(%{"tracking_id" => "order:99", "bot_ids" => [1, 5, 12]})

      assert Dispatcher.parse_signal(json) ==
               {:ok, %{"tracking_id" => "order:99", "bot_ids" => [1, 5, 12]}}
    end

    test "returns error for invalid JSON" do
      assert Dispatcher.parse_signal("not json") == {:error, :invalid_json}
    end

    test "returns error for missing fields" do
      json = Jason.encode!(%{"tracking_id" => "order:99"})

      assert Dispatcher.parse_signal(json) == {:error, :missing_fields}
    end
  end
end
