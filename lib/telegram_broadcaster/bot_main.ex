defmodule TelegramBroadcaster.BotMain do
  use Ecto.Schema

  @primary_key {:bot_id, :id, autogenerate: true}
  schema "bot_main" do
    field :bot_name, :string
    field :bot_token, :string
  end
end
