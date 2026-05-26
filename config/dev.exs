import Config

config :telegram_broadcaster,
  redis_url: System.get_env("REDIS_URL") || "redis://redis:6379/",
  mysql_url: System.get_env("MYSQL_URL") || "ecto://root:root@mysql/feliks_yii"
