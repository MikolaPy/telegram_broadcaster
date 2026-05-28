defmodule TelegramBroadcaster.IntegrationSubscriberTest do
  use ExUnit.Case, async: false

  alias TelegramBroadcaster.{BotWorker, Dispatcher, DeliveredStore}

  @redis_key "telegram:dispatch:track_test1:bot:52"
  @delivered_key "telegram:delivered:track_test1:bot:52"
  @tracking_id "track_test1"
  @driver_count 300

  setup do
    case Registry.lookup(TelegramBroadcaster.BotRegistry, 52) do
      [{pid, _}] ->
        if Process.alive?(pid), do: GenServer.stop(pid, :shutdown)
      [] ->
        :ok
    end

    Redix.command(TelegramBroadcaster.Redis, ["DEL", @redis_key])
    Redix.command(TelegramBroadcaster.Redis, ["DEL", @delivered_key])

    start_supervised!({BotWorker, bot_id: 52, bot_token: "fake_token"})
    :ok
  end

  # test "sync_driver: send, update, delete single driver" do
  #   chat_id = "1868637080"
  #
  #   # === Version 1: отправка ===
  #   put_dispatch_field(chat_id, 1, "Привет, водитель!")
  #   sync_driver(chat_id)
  #   assert :ok == wait_until_delivered_field(52, @tracking_id, chat_id, timeout_ms: 2_000)
  #
  #   delivered = DeliveredStore.fetch_field(52, @tracking_id, chat_id)
  #   assert delivered["version"] == 1
  #   assert delivered["msg_id"] != nil
  #
  #   # === Version 2: обновление ===
  #   put_dispatch_field(chat_id, 2, "Новая цена!")
  #   sync_driver(chat_id)
  #   assert :ok == wait_until_delivered_version(52, @tracking_id, chat_id, 2, timeout_ms: 2_000)
  #
  #   delivered = DeliveredStore.fetch_field(52, @tracking_id, chat_id)
  #   assert delivered["version"] == 2
  #
  #   # === Version 3: удаление ===
  #   Redix.command(TelegramBroadcaster.Redis, ["HDEL", @redis_key, chat_id])
  #   sync_driver(chat_id)
  #   assert :ok == wait_until_delivered_empty_field(52, @tracking_id, chat_id, timeout_ms: 2_000)
  # end

  test "sync all v1 then sync_driver v2 for one driver while sends in-flight" do
    target_chat_id = "42"

    # === sync: отправка v1 всем 300 водителям ===
    put_dispatch(@driver_count, 1, "Привет! Водителям.")
    sync()

    # Через 500мс大部分 ещё не отправлены — в insert_queue/in_flight
    Process.sleep(3500)
    print_delivery_snapshot("After sync v1 (500ms)", 52, @tracking_id, @driver_count)

    # === sync_driver: обновляем одного водителя до v2 ===
    put_dispatch_field(target_chat_id, 2, "Личное обновление!")
    sync_driver(target_chat_id)

    Process.sleep(1500)

    # Ждём пока конкретный водитель получит v2
    # assert :ok == wait_until_delivered_version(52, @tracking_id, target_chat_id, 2, timeout_ms: 5_000)
    # print_delivery_snapshot("After sync_driver v2 for #{target_chat_id}", 52, @tracking_id, @driver_count)

    delivered_target = DeliveredStore.fetch_field(52, @tracking_id, target_chat_id)
    assert delivered_target["version"] == 2
    assert delivered_target["msg_id"] != nil

    # Остальные водители в итоге получают v1
    assert :ok == wait_until_delivered_count(52, @tracking_id, @driver_count, timeout_ms: 15_000)
    print_delivery_snapshot("All delivered", 52, @tracking_id, @driver_count)

    delivered = DeliveredStore.fetch(52, @tracking_id)
    assert map_size(delivered) == @driver_count

    # Все кроме target_chat_id имеют version 1
    for {cid, entry} <- delivered, cid != target_chat_id do
      assert entry["version"] == 1, "chat_id=#{cid} should have version 1"
    end
  end

  # test "send, update, delete 300 drivers" do
  #   # === Version 1 ===
  #   put_dispatch(@driver_count, 1, "Привет! Водителям.")
  #   sync()
  #   Process.sleep(1_000)
  #
  #   # # === Version 2 (обновление) ===
  #   # put_dispatch(@driver_count, 2, "Обновление! Новая цена.")
  #   # sync()
  #   # Process.sleep(5_000)
  #
  #   # === Version 3 (удаление — чистим dispatch) ===
  #   Redix.command(TelegramBroadcaster.Redis, ["DEL", @redis_key])
  #   sync()
  #
  #   assert :ok == wait_until_delivered_empty(52, @tracking_id, timeout_ms: 10_000)
  # end

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

  defp sync_driver(chat_id) do
    Dispatcher.handle_sync_signal(
      "{\"tracking_id\": \"#{@tracking_id}\", \"bot_ids\": [52], \"chat_id\": \"#{chat_id}\"}"
    )
  end

  defp put_dispatch_field(chat_id, version, text) do
    payload = Jason.encode!(%{"text" => text, "markup" => %{}, "version" => version})
    {:ok, _} = Redix.command(TelegramBroadcaster.Redis, ["HSET", @redis_key, chat_id, payload])
  end

  defp print_delivery_snapshot(label, bot_id, tracking_id, driver_count) do
    dispatched = TelegramBroadcaster.DispatchStore.fetch(bot_id, tracking_id)
    delivered = DeliveredStore.fetch(bot_id, tracking_id)

    dispatched_ids = Map.keys(dispatched) |> MapSet.new()
    delivered_ids = Map.keys(delivered) |> MapSet.new()

    sent = MapSet.intersection(dispatched_ids, delivered_ids)
    pending = MapSet.difference(dispatched_ids, delivered_ids)
    orphaned = MapSet.difference(delivered_ids, dispatched_ids)

    v_counts =
      delivered
      |> Enum.map(fn {_cid, %{"version" => v}} -> v end)
      |> Enum.frequencies()

    bar =
      Enum.map(1..driver_count, fn i ->
        cid = Integer.to_string(i)

        cond do
          Map.has_key?(delivered, cid) and Map.has_key?(dispatched, cid) ->
            v = delivered[cid]["version"]
            Integer.to_string(rem(v, 10))

          Map.has_key?(delivered, cid) ->
            "x"

          Map.has_key?(dispatched, cid) ->
            "."

          true ->
            " "
        end
      end)
      |> Enum.join("")

    IO.puts("""

    ┌─ #{label} ─────────────────────────────────────────
    │ Drivers: #{driver_count}  Dispatched: #{map_size(dispatched)}  Delivered: #{map_size(delivered)}
    │ Sent: #{MapSet.size(sent)}  Pending: #{MapSet.size(pending)}  Orphaned: #{MapSet.size(orphaned)}
    │ Versions: #{inspect(v_counts)}
    │ [#{bar}]
    └─────────────────────────────────────────────────────
    """)
  end

  defp wait_until_delivered_field(bot_id, tracking_id, chat_id, opts) do
    timeout = Keyword.fetch!(opts, :timeout_ms)
    deadline = System.monotonic_time(:millisecond) + timeout
    poll_delivered_field(bot_id, tracking_id, chat_id, deadline)
  end

  defp poll_delivered_field(bot_id, tracking_id, chat_id, deadline) do
    if DeliveredStore.fetch_field(bot_id, tracking_id, chat_id) != nil do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        flunk("Timeout waiting for DeliveredStore field #{chat_id}")
      end
      Process.sleep(50)
      poll_delivered_field(bot_id, tracking_id, chat_id, deadline)
    end
  end

  defp wait_until_delivered_version(bot_id, tracking_id, chat_id, version, opts) do
    timeout = Keyword.fetch!(opts, :timeout_ms)
    deadline = System.monotonic_time(:millisecond) + timeout
    poll_delivered_version(bot_id, tracking_id, chat_id, version, deadline)
  end

  defp poll_delivered_version(bot_id, tracking_id, chat_id, version, deadline) do
    delivered = DeliveredStore.fetch_field(bot_id, tracking_id, chat_id)

    if delivered && delivered["version"] == version do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        flunk("Timeout waiting for version #{version} at #{chat_id}. Got: #{inspect(delivered)}")
      end
      Process.sleep(50)
      poll_delivered_version(bot_id, tracking_id, chat_id, version, deadline)
    end
  end

  defp wait_until_delivered_empty_field(bot_id, tracking_id, chat_id, opts) do
    timeout = Keyword.fetch!(opts, :timeout_ms)
    deadline = System.monotonic_time(:millisecond) + timeout
    poll_delivered_empty_field(bot_id, tracking_id, chat_id, deadline)
  end

  defp poll_delivered_empty_field(bot_id, tracking_id, chat_id, deadline) do
    if DeliveredStore.fetch_field(bot_id, tracking_id, chat_id) == nil do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        flunk("Timeout waiting for DeliveredStore field #{chat_id} to be removed")
      end
      Process.sleep(50)
      poll_delivered_empty_field(bot_id, tracking_id, chat_id, deadline)
    end
  end

  defp wait_until_delivered_count(bot_id, tracking_id, count, opts) do
    timeout = Keyword.fetch!(opts, :timeout_ms)
    deadline = System.monotonic_time(:millisecond) + timeout
    poll_delivered_count(bot_id, tracking_id, count, deadline)
  end

  defp poll_delivered_count(bot_id, tracking_id, count, deadline) do
    delivered = DeliveredStore.fetch(bot_id, tracking_id)

    if map_size(delivered) >= count do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        flunk("Timeout waiting for DeliveredStore count >= #{count}. Got: #{map_size(delivered)}")
      end

      Process.sleep(50)
      poll_delivered_count(bot_id, tracking_id, count, deadline)
    end
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
