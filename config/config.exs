import Config

config :telegram_broadcaster,
  redis_url: System.get_env("REDIS_URL") || "redis://redis:6379/",
  mysql_url: System.get_env("MYSQL_URL") || "ecto://root:root@mysql/feliks_yii",
  tick_interval_ms: 33

mysql_url = System.get_env("MYSQL_URL") || "ecto://root:root@mysql/feliks_yii"

config :telegram_broadcaster, TelegramBroadcaster.Repo,
  url: mysql_url,
  pool_size: 5

config :logger, level: :info

import_config "#{config_env()}.exs"
