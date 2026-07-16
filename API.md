# GoNow API

Этот файл — живой контракт HTTP API GoNow. Он описывает только уже реализованные маршруты, а не планируемые функции.

## Правило обновления

**Любое изменение backend API должно сопровождаться обновлением этого файла в том же pull request / коммите.** Для каждой новой или изменённой ручки нужно указать: метод и путь, назначение, авторизацию, тело запроса, успешный ответ, коды ошибок, ограничения и примеры. Если ручка удаляется, её нужно удалить или отметить устаревшей.

Интерактивная спецификация, генерируемая сервером: `/api/docs`. Машиночитаемый OpenAPI JSON: `/api/openapi.json`.

## Базовые адреса

| Окружение | Base URL |
| --- | --- |
| Локальная разработка | `http://127.0.0.1:8080` |
| API-префикс | `http://127.0.0.1:8080/api/v1` |

Production URL ещё не настроен. До его появления не использовать localhost-конфигурацию в Release-сборках клиентов.

## Общие правила

- Все запросы и ответы, кроме `/health`, используют JSON и заголовок `Content-Type: application/json`.
- Поля JSON пишутся в `camelCase`.
- Защищённые ручки требуют `Authorization: Bearer <accessToken>`.
- Access token — JWT. Refresh token передаётся только в body ручек refresh/logout.
- Успешные бизнес-ответы обёрнуты в объект `data`.
- Ошибки обёрнуты в объект `error`; сервер также добавляет заголовок `x-request-id` для диагностики.

### Успешный ответ

```json
{
  "data": {}
}
```

### Ошибка

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Проверьте корректность введённых данных",
    "fields": {
      "email": "Введите корректный email"
    },
    "requestId": "0bfabfd8-e5e9-4a79-8ef4-5a69bc9595e7"
  }
}
```

`fields` присутствует только у ошибок валидации и некоторых конфликтов. `requestId` нужно передавать в поддержку или прикладывать к bug report.

## Модели

### Device

Сведения об устройстве обязательны при регистрации и входе. Они позволяют хранить отдельные refresh-сессии.

```json
{
  "deviceId": "stable-device-identifier",
  "deviceName": "iPhone 17",
  "platform": "ios"
}
```

| Поле | Тип | Ограничения |
| --- | --- | --- |
| `deviceId` | string | Обязательное, до 128 символов |
| `deviceName` | string | Обязательное, до 128 символов |
| `platform` | string | `ios`, `android` или `web` |

### User

```json
{
  "id": "797d0322-3593-4521-a6e5-9c41a688263d",
  "email": "user@example.com",
  "displayName": "Николай",
  "emailVerified": false,
  "createdAt": "2026-07-16T12:00:00Z"
}
```

### Tokens

```json
{
  "accessToken": "<JWT>",
  "refreshToken": "<opaque token>",
  "accessTokenExpiresAt": "2026-07-16T12:15:00Z"
}
```

Access token живёт 15 минут по умолчанию. Refresh token живёт 30 дней по умолчанию и является одноразовым: при успешном обновлении сессии старый refresh token отзывается, а клиент получает новый.

---

## Health

### `GET /health`

Проверяет доступность PostgreSQL и Redis. Не требует авторизации и не использует стандартную обёртку `data`.

**Успех: `200 OK`**

```json
{
  "status": "ok",
  "services": {
    "postgres": "ok",
    "redis": "ok"
  }
}
```

**Деградация: `503 Service Unavailable`**

```json
{
  "status": "degraded",
  "services": {
    "postgres": "unavailable",
    "redis": "ok"
  }
}
```

---

## Аутентификация

### `POST /api/v1/auth/register`

Создаёт пользователя и первую сессию устройства. Email нормализуется: пробелы по краям удаляются, регистр приводится к нижнему.

**Авторизация:** не требуется.

**Ограничение частоты:** по IP, 5 попыток за 15 минут по умолчанию.

**Тело запроса**

```json
{
  "email": "user@example.com",
  "password": "correct-horse-battery-staple",
  "displayName": "Николай",
  "device": {
    "deviceId": "ios-installation-id",
    "deviceName": "iPhone",
    "platform": "ios"
  }
}
```

| Поле | Правило |
| --- | --- |
| `email` | Должен содержать `@`, максимум 254 символа |
| `password` | От 8 до 128 символов по умолчанию, без управляющих символов |
| `displayName` | От 2 до 80 символов после trim |
| `device` | См. модель Device |

**Успех: `201 Created`**

```json
{
  "data": {
    "user": { "id": "uuid", "email": "user@example.com", "displayName": "Николай", "emailVerified": false, "createdAt": "2026-07-16T12:00:00Z" },
    "tokens": { "accessToken": "<JWT>", "refreshToken": "<opaque token>", "accessTokenExpiresAt": "2026-07-16T12:15:00Z" }
  }
}
```

**Ошибки**

| Код HTTP | `error.code` | Причина |
| --- | --- | --- |
| `409` | `EMAIL_ALREADY_EXISTS` | Email уже зарегистрирован; в `fields.email` есть текст для формы |
| `422` | `VALIDATION_ERROR` | Некорректны email, пароль, имя или данные устройства |
| `429` | `RATE_LIMITED` | Превышен лимит регистрации |
| `503` | `SERVICE_UNAVAILABLE` | Redis недоступен для проверки лимита |

### `POST /api/v1/auth/login`

Проверяет пароль и создаёт новую refresh-сессию для указанного устройства. Предыдущие сессии других устройств не отзываются.

**Авторизация:** не требуется.

**Ограничение частоты:** по IP и email, 10 попыток за 15 минут по умолчанию.

**Тело запроса**

```json
{
  "email": "user@example.com",
  "password": "correct-horse-battery-staple",
  "device": {
    "deviceId": "ios-installation-id",
    "deviceName": "iPhone",
    "platform": "ios"
  }
}
```

**Успех: `200 OK`** — формат `data.user` и `data.tokens` такой же, как у регистрации.

**Ошибки**

| Код HTTP | `error.code` | Причина |
| --- | --- | --- |
| `401` | `INVALID_CREDENTIALS` | Неверный email или пароль |
| `403` | `USER_DISABLED` | Учётная запись неактивна |
| `422` | `VALIDATION_ERROR` | Некорректны email, пароль или данные устройства |
| `429` | `RATE_LIMITED` | Превышен лимит входа |
| `503` | `SERVICE_UNAVAILABLE` | Redis недоступен |

### `POST /api/v1/auth/refresh`

Обновляет сессию и ротирует refresh token. Клиент обязан атомарно заменить оба сохранённых токена новыми значениями из ответа. Повторно использовать предыдущий refresh token нельзя.

**Авторизация:** не требуется; refresh token передаётся в body.

**Ограничение частоты:** по IP, 30 попыток за 15 минут по умолчанию.

**Тело запроса**

```json
{
  "refreshToken": "<opaque token>"
}
```

**Успех: `200 OK`** — формат `data.user` и `data.tokens` такой же, как у регистрации.

**Ошибки**

| Код HTTP | `error.code` | Причина |
| --- | --- | --- |
| `401` | `INVALID_REFRESH_TOKEN` | Токен отсутствует в сессиях, слишком короткий или истёк |
| `401` | `SESSION_REVOKED` | Сессия уже завершена или токен использован повторно |
| `403` | `USER_DISABLED` | Учётная запись неактивна |
| `429` | `RATE_LIMITED` | Превышен лимит refresh-запросов |
| `503` | `SERVICE_UNAVAILABLE` | Redis недоступен |

### `POST /api/v1/auth/logout`

Отзывает сессию, соответствующую refresh token. Повторный logout безопасен: сервер ответит успехом, даже если токен уже был отозван или не найден.

**Авторизация:** не требуется; refresh token передаётся в body.

**Тело запроса**

```json
{
  "refreshToken": "<opaque token>"
}
```

**Успех: `200 OK`**

```json
{
  "data": {}
}
```

---

## Пользователь

### `GET /api/v1/users/me`

Возвращает профиль текущего пользователя.

**Авторизация:** обязательна.

```http
Authorization: Bearer <accessToken>
```

**Успех: `200 OK`**

```json
{
  "data": {
    "id": "797d0322-3593-4521-a6e5-9c41a688263d",
    "email": "user@example.com",
    "displayName": "Николай",
    "emailVerified": false,
    "createdAt": "2026-07-16T12:00:00Z"
  }
}
```

**Ошибки**

| Код HTTP | `error.code` | Причина |
| --- | --- | --- |
| `401` | `UNAUTHORIZED` | Нет Bearer token, токен некорректен, истёк или пользователь не найден |
| `403` | `USER_DISABLED` | Учётная запись неактивна |

## Клиентский сценарий сессии

1. После register/login сохранить `accessToken`, `refreshToken` и время истечения access token в защищённом хранилище.
2. Для защищённых маршрутов передавать access token в `Authorization`.
3. При `401` из-за истёкшего access token вызвать `/auth/refresh` один раз.
4. Атомарно заменить старые tokens ответом refresh и повторить исходный запрос.
5. Если refresh вернул `401`, очистить токены и показать вход.
6. При выходе вызвать `/auth/logout`, после чего удалить токены локально, даже если сеть недоступна.

## Примеры cURL

```bash
curl -X POST http://127.0.0.1:8080/api/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"user@example.com","password":"correct-horse-battery-staple","displayName":"Николай","device":{"deviceId":"dev-1","deviceName":"iPhone","platform":"ios"}}'
```

```bash
curl http://127.0.0.1:8080/api/v1/users/me \
  -H 'Authorization: Bearer <accessToken>'
```
