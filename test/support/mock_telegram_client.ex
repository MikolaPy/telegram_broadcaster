defmodule TelegramBroadcaster.MockTelegramClient do
  @moduledoc false

  @delay_ms 150

  @spec send_message(String.t(), String.t(), String.t(), map() | nil) ::
          {:ok, integer()} | {:error, term()}
  def send_message(_token, chat_id, text, _reply_markup \\ nil) do
    message_id = :rand.uniform(100_000)
    IO.puts("[MockTelegramClient] send_message message_id=#{message_id} chat_id=#{chat_id} text=#{String.slice(text, 0, 80)}")
    Process.sleep(@delay_ms)
    {:ok, message_id}
  end

  @spec delete_message(String.t(), String.t(), integer()) :: :ok | {:error, term()}
  def delete_message(_token, chat_id, message_id) do
    IO.puts("[MockTelegramClient] delete_message chat_id=#{chat_id} message_id=#{message_id}")
    Process.sleep(@delay_ms)
    :ok
  end
end
