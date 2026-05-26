import Config

config :telegram_broadcaster,
  redis_url: "redis://redis:6379/",
  tick_interval_ms: 33,
  redis_module: TelegramBroadcaster.TestRedis

config :logger, level: :warning
