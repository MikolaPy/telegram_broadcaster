defmodule TelegramBroadcaster.Scheduler do
  @spec next_action(map()) ::
          {:send, String.t(), tuple()}
          | {:delete, String.t(), tuple()}
          | :empty
  def next_action(tracked) when map_size(tracked) == 0, do: :empty

  def next_action(tracked) do
    # Priority: delete > insert across all tracking_ids
    case find_delete(tracked) do
      nil ->
        case find_insert(tracked) do
          nil -> :empty
          result -> result
        end

      result ->
        result
    end
  end

  defp find_delete(tracked) do
    Enum.find_value(tracked, fn {tracking_id, state} ->
      case state.delete_queue do
        [item | _] -> {:delete, tracking_id, item}
        [] -> nil
      end
    end)
  end

  defp find_insert(tracked) do
    Enum.find_value(tracked, fn {tracking_id, state} ->
      case state.insert_queue do
        [item | _] -> {:send, tracking_id, item}
        [] -> nil
      end
    end)
  end
end
