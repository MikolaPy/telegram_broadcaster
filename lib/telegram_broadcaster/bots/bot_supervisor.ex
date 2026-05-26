defmodule TelegramBroadcaster.BotSupervisor do
  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_bot(bot_id, bot_token) do
    spec = {TelegramBroadcaster.BotWorker, bot_id: bot_id, bot_token: bot_token}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
