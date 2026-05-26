defmodule TelegramBroadcaster.TelegramClientTest do
  use ExUnit.Case, async: true

  alias TelegramBroadcaster.TelegramClient

  describe "send_message/4" do
    test "returns {:ok, message_id} on success" do
      # TelegramClient uses Finch, we'll test with a mock HTTP response
      # For now, test the response parsing
      response = %{
        "ok" => true,
        "result" => %{"message_id" => 47852}
      }

      assert TelegramClient.parse_send_response(response) == {:ok, 47852}
    end

    test "returns {:error, reason} on failure" do
      response = %{
        "ok" => false,
        "description" => "Bad Request: chat not found"
      }

      assert TelegramClient.parse_send_response(response) ==
               {:error, "Bad Request: chat not found"}
    end
  end

  describe "build_send_url/1" do
    test "builds correct Telegram API URL" do
      url = TelegramClient.build_send_url("123456:ABC")
      assert url == "https://api.telegram.org/bot123456:ABC/sendMessage"
    end
  end

  describe "build_delete_url/1" do
    test "builds correct deleteMessage URL" do
      url = TelegramClient.build_delete_url("123456:ABC")
      assert url == "https://api.telegram.org/bot123456:ABC/deleteMessage"
    end
  end
end
