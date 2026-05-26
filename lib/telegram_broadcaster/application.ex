defmodule TelegramBroadcaster.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Finch, name: TelegramBroadcaster.Finch},
        {Registry, keys: :unique, name: TelegramBroadcaster.BotRegistry}
      ]
      |> maybe_add_redis()
      |> maybe_add_subscriber()

    opts = [strategy: :one_for_one, name: TelegramBroadcaster.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_redis(children) do
    if Mix.env() == :test do
      # In test mode, use TestRedis (Agent-based mock)
      children
    else
      redis_url = Application.fetch_env!(:telegram_broadcaster, :redis_url)
      child = Supervisor.child_spec({Redix, redis_url}, id: :redix)
      children ++ [child]
    end
  end

  defp maybe_add_subscriber(children) do
    if Mix.env() == :test do
      children
    else
      children ++ [TelegramBroadcaster.BotSupervisor, TelegramBroadcaster.Subscriber]
    end
  end
end
