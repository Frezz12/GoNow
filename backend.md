# Запуск backend GoNow

## Требования

- Rust и Cargo (версия не ниже 1.95);
- Docker Desktop с запущенным Docker daemon;
- Docker Compose.

`sqlx-cli` нужен только для ручного управления миграциями:

```bash
cargo install sqlx-cli --no-default-features --features rustls,postgres
```

## Первый запуск

В корне репозитория создайте локальную конфигурацию. Файл `.env` игнорируется Git и не должен содержать production-секреты в development-окружении.

```bash
cp .env.example .env
make start-infrastructure
make backend-dev
```

`make backend-dev` передаёт переменные из `.env`, запускает Rust API на `http://127.0.0.1:8080` и автоматически применяет миграции.

Проверьте зависимости и API в отдельном терминале:

```bash
curl http://localhost:8080/health
```

Ожидаемый ответ:

```json
{
  "status": "ok",
  "services": {
    "postgres": "ok",
    "redis": "ok"
  }
}
```

OpenAPI: `http://localhost:8080/api/openapi.json`; интерактивная документация: `http://localhost:8080/api/docs`.

## Полезные команды

```bash
make stop-infrastructure
make migrate
make backend-test
make backend-integration-test
```

`backend-integration-test` запускайте после старта инфраструктуры и API. Сброс development-базы: `make reset-development-database`; команда требует `APP_ENV=development` и подтверждение `RESET`.

## Миграции

```bash
cd apps/backend
cargo sqlx migrate add <name>
cargo sqlx migrate run
cargo sqlx migrate revert
```

Не используйте development `.env` и локальные Docker volumes для production.
