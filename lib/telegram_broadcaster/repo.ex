defmodule TelegramBroadcaster.Repo do
  use Ecto.Repo, otp_app: :telegram_broadcaster, adapter: Ecto.Adapters.MyXQL
end
