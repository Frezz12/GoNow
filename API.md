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

- Все запросы и ответы, кроме `/health`, используют JSON и заголовок `Content-Type: application/json`. Исключения: загрузка фотографий использует `multipart/form-data`, скачивание фотографии возвращает байты изображения.
- Поля JSON пишутся в `camelCase`.
- Защищённые ручки требуют `Authorization: Bearer <accessToken>`.
- Access token — JWT. Refresh token передаётся только в body ручек refresh/logout.
- Успешные бизнес-ответы обёрнуты в объект `data`.
- Ошибки обёрнуты в объект `error`; сервер также добавляет заголовок `x-request-id` для диагностики.

## Погода

### `GET /api/v1/weather/current`

Возвращает город и текущую погоду для координат: температуру, ощущаемую температуру, влажность, ветер и погодный код. Название города возвращается на языке параметра `locale`. Ручка публичная: она используется клиентами как прокси к погодному провайдеру, чтобы VPN/DNS на устройстве не мешали загрузке виджета.

| Параметр query | Тип | Обязателен | Описание |
| --- | --- | --- | --- |
| `latitude` | number | Да | Широта в диапазоне `-90...90`. |
| `longitude` | number | Да | Долгота в диапазоне `-180...180`. |
| `unit` | string | Да | `celsius` или `fahrenheit`. |
| `locale` | string | Нет | Локаль названия города: `ru`, `en`, `en-US`, `de`, `fr`, `es`, `pt-BR` или `zh-Hans`. По умолчанию `en`; неподдерживаемые значения безопасно заменяются на `en`. |

Пример запроса на русском языке:

```http
GET /api/v1/weather/current?latitude=55.7558&longitude=37.6173&unit=celsius&locale=ru
```

Успешный ответ — `200 OK`:

```json
{
  "data": {
    "city": "Москва",
    "temperature": 21.4,
    "apparentTemperature": 20.9,
    "relativeHumidity": 58.0,
    "windSpeed": 8.4,
    "unit": "celsius",
    "weatherCode": 1,
    "isDay": true
  }
}
```

| Поле `data` | Тип | Описание |
| --- | --- | --- |
| `city` | string \| null | Название города на языке `locale`, определённое по тем же координатам, что и прогноз. |
| `temperature` | number | Текущая температура в запрошенной единице. |
| `apparentTemperature` | number | Ощущаемая температура. |
| `relativeHumidity` | number | Относительная влажность в процентах. |
| `windSpeed` | number | Скорость ветра в км/ч. |
| `weatherCode` | integer | Погодный код WMO для отображения иконки. |
| `isDay` | boolean | `true`, если на координатах сейчас день. |

Ошибки: `422` для неверных параметров, `503` если погодный провайдер временно недоступен. Ограничения внешнего API применяются на стороне сервера; ключ не требуется.

Для названия города backend выполняет обратное геокодирование с локалью клиента и кэширует результат на 24 часа для координатной ячейки примерно 1 км. Язык включён в ключ кэша, поэтому названия на разных языках не смешиваются. Если сервис определения города временно недоступен, `city` возвращается как `null`, но погода продолжает работать. Источник данных места отображается в раскрытом погодном виджете.

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
  "birthDate": null,
  "city": null,
  "occupation": null,
  "bio": null,
  "interests": [],
  "rating": 5.0,
  "relationshipStatus": null,
  "locationLabel": null,
  "latitude": null,
  "longitude": null,
  "showDistance": true,
  "profileComplete": false,
  "createdAt": "2026-07-16T12:00:00Z"
}
```

Этот объект возвращается внутри `data.user` из `verify-email`, `reset-password`, `login` и `refresh`, а также напрямую из `GET`/`PATCH /api/v1/users/me`.

### Tokens

```json
{
  "accessToken": "<JWT>",
  "refreshToken": "<opaque token>",
  "accessTokenExpiresAt": "2026-07-16T12:15:00Z"
}
```

Access token живёт 15 минут по умолчанию. Refresh token живёт 30 дней по умолчанию и является одноразовым: при успешном обновлении сессии старый refresh token отзывается, а клиент получает новый.

### ProfilePhoto

```json
{
  "id": "4d5c7d32-3593-4521-a6e5-9c41a688263d",
  "contentType": "image/jpeg",
  "bytes": 245120,
  "createdAt": "2026-07-17T12:00:00Z",
  "contentPath": "users/me/photos/4d5c7d32-3593-4521-a6e5-9c41a688263d/content"
}
```

`contentPath` — относительный путь от API base URL (`/api/v1`). Для скачивания также нужен access token; URL R2 и его ключи клиенту не передаются.

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

Создаёт неподтверждённого пользователя и отправляет шестизначный код через Resend. Email нормализуется: пробелы по краям удаляются, регистр приводится к нижнему. Сессия создаётся только после `/auth/verify-email`. Если пользователь уже существует, но ещё не подтвердил email, повторный вызов создаёт и отправляет новый код (`200 OK`).

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
  "data": { "email": "user@example.com", "verificationRequired": true, "expiresAt": "2026-07-16T12:10:00Z" }
}
```

**Ошибки**

| Код HTTP | `error.code` | Причина |
| --- | --- | --- |
| `409` | `EMAIL_ALREADY_EXISTS` | Email уже зарегистрирован; в `fields.email` есть текст для формы |
| `422` | `VALIDATION_ERROR` | Некорректны email, пароль, имя или данные устройства |
| `429` | `RATE_LIMITED` | Превышен лимит регистрации |
| `503` | `SERVICE_UNAVAILABLE` | Redis недоступен для проверки лимита или Resend не смог принять письмо |

### `POST /api/v1/auth/verify-email`

Подтверждает шестизначный код из письма и только после этого создаёт пользовательскую сессию.

**Тело:** `email`, `code`, `device` (та же модель Device, что у register/login).

**Успех: `200 OK`** — возвращает `data.user` и `data.tokens` в формате AuthData.

**Ошибки:** `401 INVALID_EMAIL_CODE` для неверного, истёкшего или использованного кода; после пяти неверных попыток код становится недействительным.

### `POST /api/v1/auth/forgot-password`

Запрашивает одноразовый шестизначный код для восстановления пароля. Если email не существует, не подтверждён или учётная запись неактивна, API всё равно возвращает успешный ответ — это не позволяет проверить наличие аккаунта по email.

**Авторизация:** не требуется. **Ограничение частоты:** по IP и email, используется лимит входа (10 попыток за 15 минут по умолчанию).

**Тело запроса:**

```json
{ "email": "user@example.com" }
```

**Успех: `202 Accepted`** — `{ "data": {} }`. Для существующего подтверждённого аккаунта письмо содержит код с тем же TTL, что и код подтверждения email.

**Ошибки:** `422 VALIDATION_ERROR` для неверного email; `429 RATE_LIMITED`; `503 SERVICE_UNAVAILABLE`, если Resend не принял письмо.

### `POST /api/v1/auth/reset-password`

Проверяет код восстановления, устанавливает новый пароль, отзывает все прежние refresh-сессии и создаёт новую сессию только для текущего устройства.

**Авторизация:** не требуется. **Ограничение частоты:** по IP и email, используется лимит входа (10 попыток за 15 минут по умолчанию).

**Тело запроса:**

```json
{
  "email": "user@example.com",
  "code": "123456",
  "password": "new-correct-horse-battery-staple",
  "device": {
    "deviceId": "ios-installation-id",
    "deviceName": "iPhone",
    "platform": "ios"
  }
}
```

**Успех: `200 OK`** — `data.user` и `data.tokens` в формате AuthData.

**Ошибки:** `401 INVALID_RESET_CODE` для неверного, использованного или истёкшего кода; `422 VALIDATION_ERROR` для нового пароля или данных устройства; `429 RATE_LIMITED` при слишком частых попытках.

### `POST /api/v1/auth/login`

Проверяет пароль и создаёт новую refresh-сессию для указанного устройства. Предыдущие сессии других устройств не отзываются. Вход доступен только после подтверждения email.

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
| `403` | `EMAIL_NOT_VERIFIED` | Email ещё не подтверждён кодом |
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
    "emailVerified": true,
    "birthDate": "1998-05-14",
    "city": "Москва",
    "occupation": "Дизайнер",
    "bio": "Люблю прогулки, новые маршруты и хорошее кофе.",
    "interests": ["прогулки", "кофе", "кино"],
    "rating": 5.0,
    "relationshipStatus": null,
    "locationLabel": null,
    "latitude": null,
    "longitude": null,
    "showDistance": true,
    "profileComplete": true,
    "createdAt": "2026-07-16T12:00:00Z"
  }
}
```

**Ошибки**

| Код HTTP | `error.code` | Причина |
| --- | --- | --- |
| `401` | `UNAUTHORIZED` | Нет Bearer token, токен некорректен, истёк или пользователь не найден |
| `403` | `USER_DISABLED` | Учётная запись неактивна |

### `PATCH /api/v1/users/me`

Обновляет анкету текущего пользователя. Аватар и галерея изменяются отдельными media-ручками ниже.

**Авторизация:** обязательна.

```json
{
  "displayName": "Николай",
  "birthDate": "1998-05-14",
  "city": "Москва",
  "occupation": "Дизайнер",
  "bio": "Люблю прогулки, новые маршруты и хорошее кофе.",
  "interests": ["прогулки", "кофе", "кино"],
  "relationshipStatus": "Не указано",
  "locationLabel": "Москва, Тверской район",
  "latitude": 55.764,
  "longitude": 37.606,
  "showDistance": true
}
```

`birthDate` и `displayName` обязательны: без даты рождения `profileComplete` равен `false`, а клиент не позволяет создавать задания или подавать заявки. `city`, `occupation` и `bio` допускают `null`, чтобы очистить поле. `interests` — массив до 12 значений.

`rating` создаётся сервером со значением `5.0` для каждого нового пользователя. Сейчас оно только читается: изменение рейтинга будет добавлено отдельной защищённой ручкой после реализации завершения активностей и отзывов; клиент не может изменить его напрямую.

`relationshipStatus` — необязательное семейное положение (до 64 символов). `locationLabel`, `latitude` и `longitude` задают личное место пользователя; координаты передаются только парой. Они возвращаются только владельцу из `/users/me` и не попадают в публичный профиль. `showDistance` управляет безопасным отображением примерного расстояния до пользователя: при `false` расстояние не возвращается вовсе, а адрес не возвращается никогда.

**Успех: `200 OK`** — актуальный объект профиля в `data`.

**Ошибки:** `401 UNAUTHORIZED`; `403 USER_DISABLED`; `422 VALIDATION_ERROR` для некорректной анкеты.

### `GET /api/v1/users/{userId}`

Возвращает безопасную публичную часть профиля для авторизованного пользователя. Точный адрес, email и координаты никогда не возвращаются. Если оба пользователя выбрали место и владелец профиля включил `showDistance`, ответ содержит округлённый `distanceKm`, например `3.0`.

```json
{
  "data": {
    "id": "797d0322-3593-4521-a6e5-9c41a688263d",
    "displayName": "Николай",
    "age": 20,
    "city": "Москва",
    "rating": 5.0,
    "distanceKm": 3.0
  }
}
```

### Фотографии профиля

Все маршруты этого раздела требуют `Authorization: Bearer <accessToken>` и работают только с фотографиями текущего пользователя. R2 bucket приватный: объект нельзя получить по его S3 URL. В ответах выдаётся `contentPath`, который нужно запросить через backend с access token.

Загрузка передаёт ровно одно поле `file` через `multipart/form-data`. Поддерживаются JPEG, PNG и WebP, проверяется сигнатура файла, максимальный размер — 8 МиБ. iOS-клиент перед отправкой сжимает фотографию до JPEG с максимальной стороной 1600 px. В галерее может быть до 12 фотографий; аватар в этот лимит не входит.

#### `GET /api/v1/users/me/photos`

Возвращает `data.avatar` (или `null`) и `data.photos` — массив объектов `ProfilePhoto`. Галерея отсортирована от новых к старым.

**Успех: `200 OK`**

```json
{
  "data": {
    "avatar": { "id": "…", "contentType": "image/jpeg", "bytes": 245120, "createdAt": "2026-07-17T12:00:00Z", "contentPath": "users/me/photos/…/content" },
    "photos": []
  }
}
```

#### `POST /api/v1/users/me/avatar`

Создаёт или заменяет единственный аватар. При успешной замене прежний объект удаляется из S3-хранилища.

**Успех: `200 OK`** — `data` содержит `ProfilePhoto` нового аватара.

#### `POST /api/v1/users/me/photos`

Добавляет одну фотографию в галерею.

**Успех: `201 Created`** — `data` содержит добавленный `ProfilePhoto`.

#### `GET /api/v1/users/me/photos/{photoId}/content`

Возвращает исходные байты фотографии и соответствующий `Content-Type`. Это защищённый маршрут, поэтому `contentPath` нельзя передавать как публичную ссылку третьим лицам.

#### `DELETE /api/v1/users/me/photos/{photoId}`

Удаляет аватар или одну фотографию галереи из базы и ставит удаление соответствующего объекта в S3-хранилище.

**Успех: `204 No Content`**.

| Код HTTP | `error.code` | Причина |
| --- | --- | --- |
| `401` | `UNAUTHORIZED` | Нет или истёк access token |
| `404` | `PHOTO_NOT_FOUND` | Фотография не принадлежит текущему пользователю или не существует |
| `409` | `PHOTO_LIMIT_REACHED` | В галерее уже 12 фотографий |
| `422` | `VALIDATION_ERROR` | Нет поля `file`, неверный тип или размер больше 8 МиБ |
| `503` | `OBJECT_STORAGE_UNAVAILABLE` / `SERVICE_UNAVAILABLE` | Хранилище не настроено или временно недоступно |

## Покрытие реализованных маршрутов

Ниже перечислены все маршруты, зарегистрированные сервером на текущий момент.

| Метод | Путь | Назначение |
| --- | --- | --- |
| `GET` | `/health` | Проверка PostgreSQL и Redis |
| `POST` | `/api/v1/auth/register` | Регистрация и отправка email-кода |
| `POST` | `/api/v1/auth/verify-email` | Подтверждение email и создание сессии |
| `POST` | `/api/v1/auth/forgot-password` | Запрос кода восстановления |
| `POST` | `/api/v1/auth/reset-password` | Сброс пароля и новая сессия |
| `POST` | `/api/v1/auth/login` | Вход по email и паролю |
| `POST` | `/api/v1/auth/refresh` | Обновление access/refresh токенов |
| `POST` | `/api/v1/auth/logout` | Отзыв текущей refresh-сессии |
| `GET` | `/api/v1/users/me` | Получение текущего профиля |
| `PATCH` | `/api/v1/users/me` | Обновление текущего профиля |
| `GET` | `/api/v1/users/{userId}` | Безопасный публичный профиль и примерное расстояние |
| `GET` | `/api/v1/users/me/photos` | Список аватара и личных фотографий |
| `POST` | `/api/v1/users/me/avatar` | Создание или замена аватара |
| `POST` | `/api/v1/users/me/photos` | Добавление фотографии в галерею |
| `GET` | `/api/v1/users/me/photos/{photoId}/content` | Авторизованное скачивание фотографии |
| `DELETE` | `/api/v1/users/me/photos/{photoId}` | Удаление аватара или фотографии |

## Клиентский сценарий сессии

1. После register приложение показывает экран ввода кода; токены появляются только после успешного `/auth/verify-email` или `/auth/login`.
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
