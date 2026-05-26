defmodule TelegramBroadcaster.DiffEngine do
  @spec compute(map(), map()) :: {list(), list()}
  def compute(desired, delivered) do
    desired_chat_ids = Map.keys(desired)
    delivered_chat_ids = Map.keys(delivered)
    all_chat_ids = Enum.uniq(desired_chat_ids ++ delivered_chat_ids)

    {to_insert, to_delete} =
      Enum.reduce(all_chat_ids, {[], []}, fn chat_id, {ins, del} ->
        d_payload = Map.get(desired, chat_id)
        d_delivered = Map.get(delivered, chat_id)

        cond do
          # New: in desired, not in delivered
          d_payload != nil and d_delivered == nil ->
            {[{chat_id, d_payload} | ins], del}

          # Removed: in delivered, not in desired
          d_payload == nil and d_delivered != nil ->
            {ins, [{chat_id, d_delivered["msg_id"]} | del]}

          # Version changed: in both, but version differs
          d_payload["version"] != d_delivered["version"] ->
            {[{chat_id, d_payload} | ins], [{chat_id, d_delivered["msg_id"]} | del]}

          # Same version: no action needed
          true ->
            {ins, del}
        end
      end)

    {Enum.reverse(to_insert), Enum.reverse(to_delete)}
  end
end
