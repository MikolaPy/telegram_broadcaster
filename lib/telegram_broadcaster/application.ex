defmodule TelegramBroadcaster.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Finch, name: TelegramBroadcaster.Finch},
        {Registry, keys: :unique, name: TelegramBroadcaster.BotRegistry},
        TelegramBroadcaster.Repo
      ]
      |> maybe_add_redis()
      |> maybe_add_subscriber()

    opts = [strategy: :one_for_one, name: TelegramBroadcaster.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_redis(children) do
    # if Mix.env() == :test do
    #   # In test mode, use TestRedis (Agent-based mock)
    #   children
    # else
    #   redis_url = Application.fetch_env!(:telegram_broadcaster, :redis_url)
    #   child = Supervisor.child_spec({Redix, redis_url}, id: :redix)
    #   children ++ [child]
    # end
    redis_url = Application.fetch_env!(:telegram_broadcaster, :redis_url)
    child = %{
      id: :redix,
      start: {Redix, :start_link, [redis_url, [name: TelegramBroadcaster.Redis]]}
    }
    children ++ [child]
  end

  defp maybe_add_subscriber(children) do
    if Mix.env() == :test do
      children
    else
      children ++
        [
          TelegramBroadcaster.BotSupervisor,
          TelegramBroadcaster.Subscriber,
          {Task, fn -> autoload_bots() end}
        ]
    end
  end

  defp autoload_bots do
    import Ecto.Query

    TelegramBroadcaster.Repo.all(
      from b in TelegramBroadcaster.BotMain,
        select: %{bot_id: b.bot_id, bot_token: b.bot_token}
    )
    |> Enum.each(fn %{bot_id: bot_id, bot_token: bot_token} ->
      TelegramBroadcaster.BotSupervisor.start_bot(bot_id, bot_token)
    end)
  end
end
