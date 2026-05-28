defmodule TelegramBroadcaster.Scheduler do
  @spec next_action(map()) ::
          {:send, String.t(), tuple()}
          | {:delete, String.t(), tuple()}
          | :empty
  def next_action(tracked) when map_size(tracked) == 0, do: :empty

  def next_action(tracked) do
    Enum.find_value(tracked, fn {tracking_id, %{actions: actions}} ->
      case actions do
        [action | _] ->
          case action do
            {:delete, chat_id, msg_id} -> {:delete, tracking_id, {chat_id, msg_id}}
            {:send, chat_id, payload} -> {:send, tracking_id, {chat_id, payload}}
          end

        [] ->
          nil
      end
    end)
  end
end
