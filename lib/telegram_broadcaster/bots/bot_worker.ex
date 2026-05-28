defmodule TelegramBroadcaster.BotWorker do
  use GenServer

  alias TelegramBroadcaster.{DiffEngine, Scheduler, DispatchStore, DeliveredStore}

  @default_tick_interval_ms 33
  @telegram_client Application.compile_env(:telegram_broadcaster, :telegram_client, TelegramBroadcaster.TelegramClient)

  # Client API

  def start_link(opts) do
    bot_id = Keyword.fetch!(opts, :bot_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(bot_id))
  end

  def trigger_sync(bot_id, tracking_id) do
    GenServer.cast(via_tuple(bot_id), {:sync, tracking_id})
  end

  def trigger_sync_driver(bot_id, tracking_id, chat_id) do
    GenServer.cast(via_tuple(bot_id), {:sync_driver, tracking_id, chat_id})
  end

  def get_state(bot_id) do
    GenServer.call(via_tuple(bot_id), :get_state)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    bot_id = Keyword.fetch!(opts, :bot_id)
    bot_token = Keyword.fetch!(opts, :bot_token)
    tick_interval = Keyword.get(opts, :tick_interval_ms, @default_tick_interval_ms)

    state = %{
      bot_id: bot_id,
      bot_token: bot_token,
      tick_interval_ms: tick_interval,
      telegram_client: @telegram_client,
      tracked: %{}
    }

    {:ok, state, {:continue, :schedule_tick}}
  end

  @impl true
  def handle_continue(:schedule_tick, state) do
    Process.send_after(self(), :tick, state.tick_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:sync, tracking_id}, state) do
    bot_id = state.bot_id

    desired = DispatchStore.fetch(bot_id, tracking_id)
    delivered = DeliveredStore.fetch(bot_id, tracking_id)
    {to_insert, to_delete} = DiffEngine.compute(desired, delivered)

    new_tracked =
      case Map.get(state.tracked, tracking_id) do
        nil ->
          if to_insert == [] and to_delete == [] do
            state.tracked
          else
            Map.put(state.tracked, tracking_id, %{
              insert_queue: to_insert,
              delete_queue: to_delete,
              in_flight: 0
            })
          end

        existing ->
          updated = %{
            existing

            | insert_queue: existing.insert_queue ++ to_insert,
              delete_queue: existing.delete_queue ++ to_delete
          }

          Map.put(state.tracked, tracking_id, updated)
      end

    # Исправлено: используем единую функцию очистки вместо дублирования
    new_tracked = clean_empty_tracking(new_tracked, tracking_id)

    {:noreply, %{state | tracked: new_tracked}}
  end

  @impl true
  def handle_cast({:sync_driver, tracking_id, chat_id}, state) do
    bot_id = state.bot_id

    desired = DispatchStore.fetch_field(bot_id, tracking_id, chat_id)
    delivered = DeliveredStore.fetch_field(bot_id, tracking_id, chat_id)

    {to_insert, to_delete} = compute_driver_diff(chat_id, desired, delivered)

    new_tracked =
      case {to_insert, to_delete} do
        {[], []} ->
          state.tracked

        _ ->
          # Исправлено: сохраняем текущий in_flight, если запись уже существовала
          existing = Map.get(state.tracked, tracking_id, empty_entry())

          updated = %{
            existing

            | insert_queue: existing.insert_queue ++ to_insert,
              delete_queue: existing.delete_queue ++ to_delete
          }

          Map.put(state.tracked, tracking_id, updated)
      end

    {:noreply, %{state | tracked: new_tracked}}
  end

  @impl true
  def handle_info({:send_result, tracking_id, chat_id, version, result}, state) do
    bot_id = state.bot_id

    case result do
      {:ok, message_id} ->
        DeliveredStore.save(bot_id, tracking_id, chat_id, message_id, version)

      {:error, reason} ->
        IO.inspect(reason, label: "Telegram send_message failed")
    end

    new_tracked =
      update_tracked_in_state(state.tracked, tracking_id, fn entry ->
        %{entry | in_flight: max(0, entry.in_flight - 1)}
      end)

      |> clean_empty_tracking(tracking_id)

    {:noreply, %{state | tracked: new_tracked}}
  end

  @impl true
  def handle_info({:delete_result, tracking_id, chat_id, result}, state) do
    bot_id = state.bot_id

    case result do
      :ok ->
        DeliveredStore.remove(bot_id, tracking_id, chat_id)

      {:error, reason} ->
        IO.inspect(reason, label: "Telegram delete_message failed")
    end

    new_tracked =
      update_tracked_in_state(state.tracked, tracking_id, fn entry ->
        %{entry | in_flight: max(0, entry.in_flight - 1)}
      end)

      |> clean_empty_tracking(tracking_id)

    {:noreply, %{state | tracked: new_tracked}}
  end

  @impl true
  def handle_info(:tick, state) do
    new_state =
      case Scheduler.next_action(state.tracked) do
        :empty ->
          state

        {:delete, tracking_id, {chat_id, msg_id}} ->
          execute_delete(state, tracking_id, chat_id, msg_id)

        {:send, tracking_id, {chat_id, payload}} ->
          execute_send(state, tracking_id, chat_id, payload)
      end

    Process.send_after(self(), :tick, state.tick_interval_ms)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.tracked, state}
  end

  # Private

  defp execute_delete(state, tracking_id, chat_id, msg_id) do
    parent = self()

    Task.start(fn ->
      result =
        state.telegram_client.delete_message(
          state.bot_token,
          chat_id,
          msg_id
        )

      send(parent, {:delete_result, tracking_id, chat_id, result})
    end)

    update_tracked(state, tracking_id, fn entry ->
      %{entry | delete_queue: tl(entry.delete_queue), in_flight: entry.in_flight + 1}
    end)
  end

  defp execute_send(state, tracking_id, chat_id, payload) do
    parent = self()

    text = Map.get(payload, "text", "")
    version = Map.get(payload, "version", 0)
    markup = Map.get(payload, "reply_markup")

    Task.start(fn ->
      result =
        state.telegram_client.send_message(
          state.bot_token,
          chat_id,
          text,
          markup
        )

      send(parent, {:send_result, tracking_id, chat_id, version, result})
    end)

    update_tracked(state, tracking_id, fn entry ->
      %{entry | insert_queue: tl(entry.insert_queue), in_flight: entry.in_flight + 1}
    end)
  end

  defp update_tracked(state, tracking_id, fun) do
    %{state | tracked: update_tracked_in_state(state.tracked, tracking_id, fun)}
  end

  # Добавлен недостающий хелпер модификации стейта
  defp update_tracked_in_state(tracked, tracking_id, fun) do
    Map.update!(tracked, tracking_id, fun)
  end

  # Добавлен недостающий хелпер очистки очередей
  defp clean_empty_tracking(tracked, tracking_id) do
    case Map.get(tracked, tracking_id) do
      %{insert_queue: [], delete_queue: [], in_flight: 0} ->
        Map.delete(tracked, tracking_id)

      _ ->
        tracked
    end
  end

  defp via_tuple(bot_id) do
    {:via, Registry, {TelegramBroadcaster.BotRegistry, bot_id}}
  end

  defp empty_entry do
    %{insert_queue: [], delete_queue: [], in_flight: 0}
  end

  defp compute_driver_diff(chat_id, desired, delivered) do
    case {desired, delivered} do
      {nil, nil} ->
        {[], []}

      {nil, %{"msg_id" => msg_id}} ->
        {[], [{chat_id, msg_id}]}

      {payload, nil} ->
        {[{chat_id, payload}], []}

      {%{"version" => v1}, %{"msg_id" => msg_id, "version" => v2}} when v1 != v2 ->
        {[{chat_id, desired}], [{chat_id, msg_id}]}

      _ ->
        {[], []}
    end
  end
end
