import Config

config :telegram_broadcaster,
  redis_url: "redis://redis:6379/",
  tick_interval_ms: 33,
  telegram_client: TelegramBroadcaster.MockTelegramClient

config :logger, level: :warning
