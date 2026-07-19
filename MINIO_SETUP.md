# GoNow — Настройка MinIO (S3 хранилище)

## Зачем нужен MinIO

GoNow использует S3-совместимое хранилище для фотографий профиля (аватар и галерея). Без настроенного хранилища загрузка фото недоступна — бэкенд возвращает ошибку `OBJECT_STORAGE_UNAVAILABLE`.

## Быстрый старт

### 1. Скачать и запустить MinIO

```bash
# Скачать MinIO (Windows)
curl -L -o minio.exe https://dl.min.io/server/minio/release/windows-amd64/minio.exe

# Запустить (данные хранятся в указанной папке)
minio.exe server C:\path\to\minio-data --console-address ":9001"
```

### 2. Создать бакет через консоль

1. Откройте http://localhost:9001
2. Войдите: логин `minioadmin`, пароль `minioadmin`
3. Нажмите "Create Bucket"
4. Имя бакета: `gonow-development`
5. Настройте доступ: "Download" (публичное чтение)

Или через MinIO Client (mc):

```bash
# Скачать mc
curl -L -o mc.exe https://dl.min.io/client/mc/release/windows-amd64/mc.exe

# Настроить alias
mc alias set gonow http://localhost:9000 minioadmin minioadmin

# Создать бакет
mc mb gonow/gonow-development

# Разрешить публичное чтение
mc anonymous set download gonow/gonow-development
```

### 3. Настроить .env

Добавьте в `.env`:

```
OBJECT_STORAGE_ENDPOINT=http://localhost:9000
OBJECT_STORAGE_BUCKET=gonow-development
OBJECT_STORAGE_ACCESS_KEY_ID=minioadmin
OBJECT_STORAGE_SECRET_ACCESS_KEY=minioadmin
OBJECT_STORAGE_REGION=us-east-1
OBJECT_STORAGE_KEY_PREFIX=gonow
OBJECT_STORAGE_FORCE_PATH_STYLE=true
```

### 4. Перезапустить бэкенд

```bash
cargo run --release
```

## Проверка

```bash
# Проверить здоровье бэкенда
curl http://localhost:8080/health

# Проверить загрузку фото (нужен валидный токен)
curl -H "Authorization: Bearer <token>" http://localhost:8080/api/v1/users/me/photos
```

## Docker (альтернатива)

Если Docker работает, MinIO можно запустить через docker-compose:

```yaml
minio:
  image: minio/minio:latest
  container_name: gonow-minio
  command: server /data --console-address ":9001"
  environment:
    MINIO_ROOT_USER: minioadmin
    MINIO_ROOT_PASSWORD: minioadmin
  ports:
    - "9000:9000"
    - "9001:9001"
  volumes:
    - gonow-minio-data:/data
```

## Другие S3-провайдеры

Бэкенд совместим с любым S3-хранилищем. Измените переменные в `.env`:

| Провайдер | ENDPOINT |
| --- | --- |
| AWS S3 | (не указывать) |
| Cloudflare R2 | `https://<account-id>.r2.cloudflarestorage.com` |
| Backblaze B2 | `https://s3.<region>.backblazeb2.com` |
| MinIO (локально) | `http://localhost:9000` |

## Структура файлов в S3

```
gonow/
  profiles/
    {user_id}/
      {photo_id}.jpg
```

## Устранение проблем

| Ошибка | Решение |
| --- | --- |
| `OBJECT_STORAGE_UNAVAILABLE` | MinIO не запущен или .env не настроен |
| `Access Denied` | Бакет не создан или нет публичного доступа |
| `Connection refused` | MinIO слушает на другом порту |
| Фото не загружаются | Проверьте `writeTimeout` в ApiClient (60 сек) |
