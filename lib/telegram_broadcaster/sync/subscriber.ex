defmodule TelegramBroadcaster.Subscriber do
  use GenServer

  alias TelegramBroadcaster.Dispatcher

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    redis_url = Application.fetch_env!(:telegram_broadcaster, :redis_url)
    {:ok, pubsub} = Redix.PubSub.start_link(redis_url, name: TelegramBroadcaster.PubSub)
    Redix.PubSub.subscribe(pubsub, "telegram:sync", self())
    {:ok, %{pubsub: pubsub}}
  end

  @impl true
  def handle_info({:redix_pubsub, _pubsub, :message, %{payload: payload}}, state) do
    Dispatcher.handle_sync_signal(payload)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
