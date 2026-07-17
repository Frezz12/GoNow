# Объектное хранилище GoNow

GoNow использует приватное S3-совместимое хранилище для аватаров и фотографий профиля. В коде нет зависимостей от Cloudflare: backend работает с endpoint, bucket, ключами и режимом адресации из переменных окружения. Поэтому Cloudflare R2 подходит для разработки, а будущая замена на AWS S3, Backblaze B2 S3, DigitalOcean Spaces, MinIO или другой S3-совместимый сервис не потребует изменений в iOS-клиенте или API.

## Настройка Cloudflare R2 для разработки

1. В Cloudflare Dashboard откройте **R2 Object Storage** и создайте отдельный bucket, например `gonow-development`. Не включайте публичный доступ: все фотографии идут через backend с access token.
2. В R2 создайте **API token** для S3 API. Дайте ему права только `Object Read & Write` только на этот development bucket. Сохраните `Access Key ID` и `Secret Access Key`: секрет показывается один раз.
3. Найдите Cloudflare Account ID и внесите значения в локальный `.env` в корне репозитория:

```env
OBJECT_STORAGE_ENDPOINT=https://<CLOUDFLARE_ACCOUNT_ID>.r2.cloudflarestorage.com
OBJECT_STORAGE_BUCKET=gonow-development
OBJECT_STORAGE_ACCESS_KEY_ID=<R2_ACCESS_KEY_ID>
OBJECT_STORAGE_SECRET_ACCESS_KEY=<R2_SECRET_ACCESS_KEY>
OBJECT_STORAGE_REGION=auto
OBJECT_STORAGE_KEY_PREFIX=gonow
OBJECT_STORAGE_FORCE_PATH_STYLE=true
```

4. Перезапустите backend: `make backend-dev`. Миграция создаст таблицу метаданных `user_photos`. После входа попробуйте изменить аватар и добавить фото в профиле.

Cloudflare R2 поддерживает S3 API; его endpoint имеет вид `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`, а S3 region для R2 — `auto`. GoNow применяет только совместимые операции `PutObject`, `GetObject` и `DeleteObject`. [Документация Cloudflare о S3 API](https://developers.cloudflare.com/r2/api/s3/api/) и [о R2 API tokens](https://developers.cloudflare.com/r2/api/tokens/).

## Безопасность и границы ответственности

- `OBJECT_STORAGE_ACCESS_KEY_ID` и `OBJECT_STORAGE_SECRET_ACCESS_KEY` — секреты backend. Они не должны попадать в Xcode, Android, клиентские логи, Git или public bucket.
- В базе хранится только object key, MIME-тип, размер, владелец и дата. Имя файла пользователя не используется в object key.
- Файлы принимаются только как JPEG, PNG или WebP с проверкой сигнатуры и лимитом 8 МиБ.
- R2 остаётся приватным. Клиент получает содержимое через `GET /api/v1/users/me/photos/{id}/content`, где проверяется JWT и владелец фотографии. Не настраивайте CORS ради текущего мобильного сценария: приложение не обращается к R2 напрямую.
- При недоступном или незаполненном object storage основной backend продолжает работать, но media-ручки вернут `503`. Это позволяет включить R2 поэтапно.

## Переход на другой S3-провайдер

Смена провайдера сводится к конфигурации и переносу объектов.

1. Создайте private bucket у нового провайдера и ключ с минимальными правами `GetObject`, `PutObject`, `DeleteObject` только для него.
2. Скопируйте объекты из старого bucket в новый, сохранив ключи `gonow/profiles/...`. Для миграции используйте средство провайдера, `rclone` или S3-to-S3 copy; сначала проверьте количество и размеры объектов.
3. В deployment secrets замените только эти переменные: `OBJECT_STORAGE_ENDPOINT`, `OBJECT_STORAGE_BUCKET`, `OBJECT_STORAGE_ACCESS_KEY_ID`, `OBJECT_STORAGE_SECRET_ACCESS_KEY`, `OBJECT_STORAGE_REGION`, при необходимости `OBJECT_STORAGE_FORCE_PATH_STYLE`.
4. **Не меняйте** `OBJECT_STORAGE_KEY_PREFIX`, пока перенос сохраняет ключи: ссылки на объекты находятся в PostgreSQL как `object_key`.
5. Перезапустите backend, проверьте загрузку, скачивание и удаление тестовой фотографии, затем только после этого отключайте старое хранилище.

Для AWS S3 оставьте `OBJECT_STORAGE_ENDPOINT` пустым, укажите настоящий AWS region (например, `eu-central-1`) и `OBJECT_STORAGE_FORCE_PATH_STYLE=false`. Для большинства альтернативных S3-провайдеров достаточно указать их documented endpoint и режим адресации. Если выбранный сервис не совместим с S3 API, понадобится новый adapter только в `apps/backend/src/infrastructure/storage.rs`; HTTP API и iOS-клиент останутся без изменений.
