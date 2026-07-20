# =========================
# Этап сборки
# =========================
FROM rust:1.95-bookworm AS builder

WORKDIR /app

# Настройки Cargo для стабильной загрузки зависимостей
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse
ENV CARGO_HTTP_TIMEOUT=600
ENV CARGO_NET_RETRY=10
ENV CARGO_HTTP_MULTIPLEXING=false

# Сначала копируем только файлы зависимостей
COPY Cargo.toml Cargo.lock ./

# Предварительно собираем зависимости для кеширования Docker-слоя
RUN mkdir -p src \
    && printf 'fn main() {}\n' > src/main.rs \
    && cargo build --release --locked \
    && rm -rf src

# Копируем исходный код проекта
COPY . .

# Пересобираем приложение с настоящими исходниками
RUN touch src/main.rs \
    && cargo build --release --locked


# =========================
# Финальный образ
# =========================
FROM debian:bookworm-slim AS runtime

# Устанавливаем сертификаты и создаём отдельного пользователя
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libssl3 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 appuser

WORKDIR /app

# Копируем собранный backend
COPY --from=builder /app/target/release/gonow-backend /usr/local/bin/gonow-backend

USER appuser

EXPOSE 8080

CMD ["/usr/local/bin/gonow-backend"]