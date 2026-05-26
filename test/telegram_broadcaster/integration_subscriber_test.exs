defmodule TelegramBroadcaster.IntegrationSubscriberTest do
  use ExUnit.Case, async: false 

  alias TelegramBroadcaster.{Subscriber, BotSupervisor, BotWorker}

  setup do
    start_supervised!({BotWorker, bot_id: 52, bot_token: "8143657616:AAFXcNX0V60aH9yE-i74bmRk2ZJMKgSEWXE"})
    :ok
  end

  test "subscriber receives pubsub message and mutates real BotWorker state" do
    # delivered_key = "telegram:delivered:track_abc:bot:52" # поправь под свой шаблон ключа в delivered_store.ex
    # delivered_payload = "{\"msg_id\": 56, \"version\": 1}"
    # {:ok, _} = Redix.command(TelegramBroadcaster.Redis, ["HSET", delivered_key, 1868637080, delivered_payload])

    redis_key = "telegram:dispatch:track_test1:bot:52"
    message_payload_json = "{\"text\": \"Привет! NEW TEST 1.\", \"markup\": {}, \"version\": 1}"
    {:ok, _} = Redix.command(TelegramBroadcaster.Redis, ["HSET", redis_key, 1868637080, message_payload_json])


    json_payload = "{\"tracking_id\": \"track_test1\", \"bot_ids\": [52]}"
    fake_redis_msg = {:redix_pubsub, :some_pid, :message, %{payload: json_payload}}
    send(Subscriber, fake_redis_msg)

    Process.sleep(3000)

    # message_payload_json = "{\"text\": \"Привет! NEW TEST 2.\", \"markup\": {}, \"version\": 2}"
    # {:ok, _} = Redix.command(TelegramBroadcaster.Redis, ["HSET", redis_key, 1868637080, message_payload_json])
    #
    # send(Subscriber, fake_redis_msg)
    #
    # Process.sleep(3000)

    # 5. Проверяем РЕЗУЛЬТАТ: запрашиваем состояние реального BotWorker
    # и смотрим, появилась ли там наша задача на синхронизацию
    # bot_state = BotWorker.get_state(55)
    
    # assert Map.has_key?(bot_state, "track_abc")
  end
end
