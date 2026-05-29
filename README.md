# Telegram Broadcaster

Elixir/Phoenix микросервис для рассылки сообщений водителям через Telegram.

Получает данные из Rails через общий Redis, отправляет/удаляет сообщения через Telegram Bot API.

## Архитектура

**Принцип:** State Reconciliation (идемпотентное выравнивание).

Rails записывает в Redis желаемое состояние (кому и что отправить). Elixir сверяет его с текущим (что уже доставлено) и выполняет diff: отправить новое, удалить лишнее.

### Компоненты

```
┌─────────────┐     PUB/SUB      ┌──────────────┐
│   Rails     │ ──────────────►  │  Subscriber   │
└─────────────┘                  └──────┬───────┘
      │                                 │
      │ HMSET (dispatch)               │ sync signal
      ▼                                 ▼
┌───────────┐                    ┌──────────────┐
│   Redis   │ ◄────────────────  │  Dispatcher   │
└───────────┘                    └──────┬───────┘
                                        │
                              ┌─────────┴─────────┐
                              │   BotWorker (×N)   │
                              │  ┌───────────────┐ │
                              │  │  DiffEngine   │ │
                              │  ├───────────────┤ │
                              │  │  Scheduler    │ │
                              │  └───────┬───────┘ │
                              └──────────┼─────────┘
                                         │
                              ┌──────────┴──────────┐
                              │  Telegram Bot API    │
                              └─────────────────────┘
```

### Модули

| Модуль | Назначение |
|--------|-----------|
| `Application` | Точка входа: запускает Finch, Registry, Redis, Repo, BotSupervisor, Subscriber |
| `Subscriber` | GenServer: подписка на Redis Pub/Sub канал `telegram:sync` |
| `Dispatcher` | Парсит sync-сигнал, маршрутизирует к BotWorker |
| `BotSupervisor` | DynamicSupervisor: управляет процессами BotWorker |
| `BotWorker` | GenServer: обработка sync, очередь действий, тик-обработка |
| `DiffEngine` | Вычисляет diff между desired и delivered состояниями |
| `Scheduler` | FIFO: выбирает следующее действие из очереди |
| `DispatchStore` | Чтение желаемого состояния из Redis |
| `DeliveredStore` | Чтение/запись доставленного состояния в Redis |
| `FailedStore` | Запись ошибочных операций в Redis |
| `TelegramClient` | HTTP-клиент для Telegram Bot API (send/delete) |

## Redis Contract

### Ключи

| Ключ | Тип | Владелец | Описание |
|------|-----|----------|----------|
| `telegram:dispatch:{tracking_id}:bot:{bot_id}` | HASH | Rails пишет, Elixir читает | Желаемое состояние. Field = chat_id, Value = JSON payload |
| `telegram:delivered:{tracking_id}:bot:{bot_id}` | HASH | Elixir читает и пишет | Доставленное состояние. Field = chat_id, Value = JSON `{msg_id, version}` |
| `telegram:failed:{tracking_id}:bot:{bot_id}` | HASH | Elixir пишет | Ошибочные операции. Field = chat_id, Value = JSON `{action, reason, timestamp}` |
| `telegram:sync` | PUB/SUB | Rails → Elixir | Сигнал «сверься» |

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

**Failed** (создаёт Elixir при ошибке):
```json
{"action": "send", "reason": "HTTP 403: Forbidden", "timestamp": 1748520000}
```

**Pub/Sub сигнал (полная синхронизация)**:
```json
{"tracking_id": "order:99", "bot_ids": [1, 5, 12]}
```

**Pub/Sub сигнал (синхронизация одного водителя)**:
```json
{"tracking_id": "order:99", "bot_ids": [15], "chat_id": "111"}
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

### Синхронизация одного водителя (sync_driver)

```
Rails:
  HSET telegram:dispatch:order:99:bot:15  111 '{"text":"...","version":2}'
  PUBLISH telegram:sync '{"tracking_id":"order:99","bot_ids":[15],"chat_id":"111"}'

Elixir:
  Dispatcher → BotWorker#15.trigger_sync_driver("order:99", "111")
  BotWorker: запрашивает только поле 111 из dispatch и delivered
  Вычисляет diff для одного chat_id, обновляет очередь
```

### Обработка ошибок

```
При ошибке send/delete:
  FailedStore.save(bot_id, tracking_id, chat_id, action, reason)
  → записывает в telegram:failed:{tracking_id}:bot:{bot_id}

При успешной отправке:
  Проверяет, не изменился ли dispatch пока летел запрос
  Если version устарел — ставит delete в очередь
```

## Два режима синхронизации

### `trigger_sync` — полная синхронизация
Считывает весь HASH dispatch и delivered, вычисляет полный diff для всех chat_id.

### `trigger_sync_driver` — точечная синхронизация
Считывает только одно поле (chat_id) из dispatch и delivered. Используется для обновления одного водителя без перечитывания всех. Заменяет действия для этого chat_id в существующей очереди.

## Структура проекта

```
lib/telegram_broadcaster/
├── application.ex              # Supervisor: запуск всех компонентов
├── repo.ex                     # Ecto Repo (MySQL)
├── bot_main.ex                 # Схема: bot_id, bot_name, bot_token
├── delivery/
│   ├── dispatch_store.ex       # Redis: чтение dispatch
│   ├── delivered_store.ex      # Redis: запись/чтение delivered
│   ├── failed_store.ex         # Redis: запись ошибок
│   ├── telegram_client.ex      # HTTP: Telegram Bot API
│   └── diff_engine.ex          # Diff: desired vs delivered
├── sync/
│   ├── subscriber.ex           # Redis Pub/Sub listener
│   └── dispatcher.ex           # Маршрутизация сигналов
├── bots/
│   ├── bot_supervisor.ex       # DynamicSupervisor
│   ├── bot_worker.ex           # GenServer: обработка и очередь
│   └── scheduler.ex            # FIFO выборка действия
└── telegram_broadcaster_web/
    └── endpoint.ex             # Plug: health check
```

## Запуск

### Docker

```bash
docker build -t telegram_broadcaster .
docker run -e REDIS_URL=redis://redis:6379/ \
           -e MYSQL_URL=ecto://root:root@mysql/feliks_yii \
           telegram_broadcaster
```

### Локально

```bash
mix deps.get
mix phx.server
```

## Конфигурация

| Переменная | По умолчанию | Описание |
|-----------|-------------|----------|
| `REDIS_URL` | `redis://redis:6379/` | URL подключения к Redis |
| `MYSQL_URL` | `ecto://root:root@mysql/feliks_yii` | URL подключения к MySQL |

Внутренние параметры (`config/config.exs`):

| Параметр | Значение | Описание |
|---------|---------|----------|
| `tick_interval_ms` | 33 | Интервал обработки действий (rate limit ~30 msg/sec) |

## Зависимости

| Пакет | Версия | Назначение |
|-------|--------|-----------|
| Phoenix | ~> 1.7 | Web framework |
| Ecto SQL | ~> 3.10 | ORM |
| MyXQL | ~> 0.6 | MySQL драйвер |
| Redix | ~> 1.2 | Redis клиент |
| Jason | ~> 1.4 | JSON |
| Finch | ~> 0.18 | HTTP клиент |
| Plug Cowboy | ~> 2.7 | Web server |
| CAStore | ~> 1.0 | SSL сертификаты |

## MySQL (bot_main)

Таблица `bot_main` — конфигурация ботов, загружается при старте:

| Поле | Тип | Описание |
|------|-----|----------|
| `bot_id` | INT (PK) | ID бота |
| `bot_name` | VARCHAR | Название бота |
| `bot_token` | VARCHAR | Telegram Bot API token |

При старте приложение читает все боты из БД и запускает по одному `BotWorker` на каждый бот.
