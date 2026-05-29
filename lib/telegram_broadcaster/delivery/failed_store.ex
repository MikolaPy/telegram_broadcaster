defmodule TelegramBroadcaster.FailedStore do
  @redis Application.compile_env(:telegram_broadcaster, :redis_module, Redix)

  @spec save(pos_integer(), String.t(), String.t(), String.t(), String.t()) :: :ok
  def save(bot_id, tracking_id, chat_id, action, reason) do
    key = "telegram:failed:#{tracking_id}:bot:#{bot_id}"
    json = Jason.encode!(%{
      "action" => action,
      "reason" => to_string(reason),
      "timestamp" => System.system_time(:second)
    })

    {:ok, _} = @redis.command(redis_name(), ["HSET", key, chat_id, json])
    :ok
  end

  @spec fetch(pos_integer(), String.t()) :: map()
  def fetch(bot_id, tracking_id) do
    key = "telegram:failed:#{tracking_id}:bot:#{bot_id}"

    case @redis.command(redis_name(), ["HGETALL", key]) do
      {:ok, []} -> %{}
      {:ok, pairs} -> parse_pairs(pairs)
    end
  end

  @spec remove(pos_integer(), String.t(), String.t()) :: :ok
  def remove(bot_id, tracking_id, chat_id) do
    key = "telegram:failed:#{tracking_id}:bot:#{bot_id}"
    {:ok, _} = @redis.command(redis_name(), ["HDEL", key, chat_id])
    :ok
  end

  defp redis_name, do: TelegramBroadcaster.Redis

  defp parse_pairs(pairs) do
    pairs
    |> Enum.chunk_every(2)
    |> Enum.into(%{}, fn [chat_id, json] ->
      {:ok, payload} = Jason.decode(json)
      {chat_id, payload}
    end)
  end
end
