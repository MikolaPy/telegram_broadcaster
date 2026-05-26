defmodule TelegramBroadcaster.Dispatcher do
  @spec parse_signal(String.t()) ::
          {:ok, map()} | {:error, :invalid_json | :missing_fields}
  def parse_signal(raw_json) do
    with {:ok, decoded} <- Jason.decode(raw_json),
         :ok <- validate_fields(decoded) do
      {:ok, decoded}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      {:error, :missing_fields} -> {:error, :missing_fields}
    end
  end

  @spec handle_sync_signal(String.t()) :: :ok
  def handle_sync_signal(raw_json) do
    case parse_signal(raw_json) do
      {:ok, %{"tracking_id" => tracking_id, "bot_ids" => bot_ids, "chat_id" => chat_id}} ->
        Enum.each(bot_ids, fn bot_id ->
          TelegramBroadcaster.BotWorker.trigger_sync_driver(bot_id, tracking_id, chat_id)
        end)

      {:ok, %{"tracking_id" => tracking_id, "bot_ids" => bot_ids}} ->
        Enum.each(bot_ids, fn bot_id ->
          TelegramBroadcaster.BotWorker.trigger_sync(bot_id, tracking_id)
        end)

      {:error, reason} ->
        require Logger
        Logger.warning("Invalid sync signal (#{reason}): #{raw_json}")
    end

    :ok
  end

  defp validate_fields(%{"tracking_id" => _, "bot_ids" => _}), do: :ok
  defp validate_fields(_), do: {:error, :missing_fields}
end
