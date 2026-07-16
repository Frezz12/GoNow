.PHONY: start-infrastructure stop-infrastructure backend-dev backend-test backend-integration-test migrate reset-development-database

start-infrastructure:
	docker compose up -d postgres redis

stop-infrastructure:
	docker compose down

backend-dev:
	@set -a; . ./.env; set +a; cd apps/backend; cargo run

backend-test:
	@set -a; . ./.env; set +a; cd apps/backend; cargo test

backend-integration-test:
	@bash apps/backend/tests/auth_api.sh

migrate:
	@set -a; . ./.env; set +a; cd apps/backend; cargo sqlx migrate run

reset-development-database:
	@test "$(APP_ENV)" = "development" || (echo "Set APP_ENV=development to reset the database"; exit 1)
	@printf "This permanently removes local GoNow development data. Type RESET: "; read answer; test "$$answer" = "RESET"
	docker compose down -v
	docker compose up -d postgres redis
