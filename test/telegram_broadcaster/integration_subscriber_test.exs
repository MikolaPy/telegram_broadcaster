defmodule TelegramBroadcaster.IntegrationSubscriberTest do
  use ExUnit.Case, async: false

  alias TelegramBroadcaster.{BotWorker, Dispatcher, DeliveredStore}

  @redis_key "telegram:dispatch:track_test1:bot:52"
  @delivered_key "telegram:delivered:track_test1:bot:52"
  @tracking_id "track_test1"
  @driver_count 300

  setup do
    case Registry.lookup(TelegramBroadcaster.BotRegistry, 52) do
      [{pid, _}] -> GenServer.stop(pid, :shutdown)
      [] -> :ok
    end

    Redix.command(TelegramBroadcaster.Redis, ["DEL", @redis_key])
    Redix.command(TelegramBroadcaster.Redis, ["DEL", @delivered_key])

    start_supervised!({BotWorker, bot_id: 52, bot_token: "fake_token"})
    :ok
  end

  test "send, update, delete 300 drivers" do
    # === Version 1 ===
    put_dispatch(@driver_count, 1, "Привет! Водителям.")
    sync()
    Process.sleep(1_000)

    # # === Version 2 (обновление) ===
    # put_dispatch(@driver_count, 2, "Обновление! Новая цена.")
    # sync()
    # Process.sleep(5_000)

    # === Version 3 (удаление — чистим dispatch) ===
    Redix.command(TelegramBroadcaster.Redis, ["DEL", @redis_key])
    sync()

    assert :ok == wait_until_delivered_empty(52, @tracking_id, timeout_ms: 10_000)
  end

  defp put_dispatch(count, version, text) do
    payload = Jason.encode!(%{"text" => text, "markup" => %{}, "version" => version})

    chat_ids = Enum.map(1..count, &Integer.to_string/1)
    args = Enum.flat_map(chat_ids, &[&1, payload])
    {:ok, _} = Redix.command(TelegramBroadcaster.Redis, ["HSET", @redis_key | args])
  end

  defp sync do
    Dispatcher.handle_sync_signal(
      "{\"tracking_id\": \"#{@tracking_id}\", \"bot_ids\": [52]}"
    )
  end

  defp wait_until_delivered_empty(bot_id, tracking_id, opts) do
    timeout = Keyword.fetch!(opts, :timeout_ms)
    deadline = System.monotonic_time(:millisecond) + timeout
    poll_delivered(bot_id, tracking_id, deadline)
  end

  defp poll_delivered(bot_id, tracking_id, deadline) do
    delivered = DeliveredStore.fetch(bot_id, tracking_id)

    if map_size(delivered) == 0 do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        flunk("Timeout waiting for DeliveredStore to empty. Remaining: #{map_size(delivered)}")
      end

      Process.sleep(50)
      poll_delivered(bot_id, tracking_id, deadline)
    end
  end

  defp wait_until_cleaned(bot_id, tracking_id, opts) do
    timeout = Keyword.fetch!(opts, :timeout_ms)
    deadline = System.monotonic_time(:millisecond) + timeout
    poll(bot_id, tracking_id, deadline)
  end

  defp poll(bot_id, tracking_id, deadline) do
    state = BotWorker.get_state(bot_id)

    if not Map.has_key?(state, tracking_id) do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        entry = Map.get(state, tracking_id)
        flunk("Timeout waiting for #{tracking_id} to clean up. Remaining: #{inspect(entry)}")
      end

      Process.sleep(50)
      poll(bot_id, tracking_id, deadline)
    end
  end
end
