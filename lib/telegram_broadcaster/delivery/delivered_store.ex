defmodule TelegramBroadcaster.DeliveredStore do
  @redis Application.compile_env(:telegram_broadcaster, :redis_module, Redix)

  @spec fetch(pos_integer(), String.t()) :: map()
  def fetch(bot_id, tracking_id) do
    key = "telegram:delivered:#{tracking_id}:bot:#{bot_id}"

    case @redis.command(redis_name(), ["HGETALL", key]) do
      {:ok, []} -> %{}
      {:ok, pairs} -> parse_pairs(pairs)
    end
  end

  @spec fetch_field(pos_integer(), String.t(), String.t()) :: map() | nil
  def fetch_field(bot_id, tracking_id, chat_id) do
    key = "telegram:delivered:#{tracking_id}:bot:#{bot_id}"

    case @redis.command(redis_name(), ["HGET", key, chat_id]) do
      {:ok, nil} -> nil
      {:ok, json} -> Jason.decode!(json)
    end
  end

  @spec save(pos_integer(), String.t(), String.t(), integer(), integer()) :: :ok
  def save(bot_id, tracking_id, chat_id, message_id, version) do
    key = "telegram:delivered:#{tracking_id}:bot:#{bot_id}"
    json = Jason.encode!(%{"msg_id" => message_id, "version" => version})
    {:ok, _} = @redis.command(redis_name(), ["HSET", key, chat_id, json])
    :ok
  end

  @spec remove(pos_integer(), String.t(), String.t()) :: :ok
  def remove(bot_id, tracking_id, chat_id) do
    key = "telegram:delivered:#{tracking_id}:bot:#{bot_id}"
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
