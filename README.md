# Telegram Broadcaster

Elixir/Phoenix микросервис для рассылки сообщений водителям через Telegram.

Получает данные из Rails через общий Redis, отправляет/удаляет сообщения через Telegram Bot API.

## Архитектура

**Принцип:** State Reconciliation (идемпотентное выравнивание).

Rails записывает в Redis желаемое состояние (кому и что отправить). Elixir сверяет его с текущим (что уже доставлено) и выполняет diff: отправить новое, удалить лишнее.

## Redis Contract

### Ключи

| Ключ | Тип | Владелец | Описание |
|------|-----|----------|----------|
| `telegram:dispatch:{tracking_id}:bot:{bot_id}` | HASH | Rails пишет, Elixir читает | Желаемое состояние. Field = chat_id, Value = JSON payload |
| `telegram:delivered:{tracking_id}:bot:{bot_id}` | HASH | Elixir читает и пишет | Доставленное состояние. Field = chat_id, Value = JSON `{msg_id, version}` |
| `telegram:sync` | PUB/SUB | Rails → Elixir | Сигнал "сверься" |

### Payload форматы

**Dispatch** (создаёт Rails):
```json
{
  "text": "🚕 Заказ #99\n01.06.2026 12:00\nAirport → Center\n4500₽",
  "reply_markup": {"inline_keyboard": [[{"text": "Принять", "callback_data": "claim:99"}]]},
  "version": 1
}
```

**Delivered** (создаёт Elixir):
```json
{"msg_id": 47852, "version": 1}
```

**Pub/Sub сигнал**:
```json
{"tracking_id": "order:99", "bot_ids": [1, 5, 12]}
```

## Data Flow

### Создание заказа

```
Rails:
  HMSET telegram:dispatch:order:99:bot:15  111 '{"text":"...","version":1}' 222 '...'
  PUBLISH telegram:sync '{"tracking_id":"order:99","bot_ids":[15]}'

Elixir:
  Subscriber → Dispatcher → BotWorker#15.trigger_sync("order:99")
  BotWorker: desired = {111, 222, 333}, delivered = {} (пусто)
  DiffEngine: to_insert = [111, 222, 333], to_delete = []

  Тик 1 (33ms): sendMessage(111) → msg_id 47852 → DeliveredStore.save
  Тик 2 (66ms): sendMessage(222) → msg_id 47853 → DeliveredStore.save
  Тик 3 (99ms): sendMessage(333) → msg_id 47854 → DeliveredStore.save
```

### Обновление заказа (version: 1 → 2)

```
DiffEngine: to_insert = [111, 222, 333] (version отличается)
            to_delete = [{111, 47852}, {222, 47853}, {333, 47854}]

Приоритет: сначала delete, потом insert
```

### Отмена заказа

```
Rails: DEL telegram:dispatch:order:99:bot:15 + PUBLISH sync
DiffEngine: desired = {}, delivered = {111, 222, 333}
→ to_delete = [{111, 47852}, {222, 47853}, {333, 47854}]
```

