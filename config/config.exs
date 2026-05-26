import Config

config :telegram_broadcaster,
  redis_url: System.get_env("REDIS_URL") || "redis://redis:6379/",
  mysql_url: System.get_env("MYSQL_URL") || "ecto://root:root@mysql/feliks_yii",
  tick_interval_ms: 33

config :logger, level: :info

import_config "#{config_env()}.exs"
