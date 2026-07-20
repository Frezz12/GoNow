# =========================
# Этап сборки
# =========================
FROM rust:1.95-bookworm AS builder

WORKDIR /app

ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse
ENV CARGO_HTTP_TIMEOUT=120
ENV CARGO_HTTP_LOW_SPEED_LIMIT=1
ENV CARGO_NET_RETRY=5
ENV CARGO_HTTP_MULTIPLEXING=false
ENV CARGO_TERM_COLOR=always

# Сначала копируем только Cargo-файлы
COPY Cargo.toml Cargo.lock ./

# Создаём временный target, чтобы Cargo мог прочитать manifest
RUN mkdir -p src \
    && printf 'fn main() {}\n' > src/main.rs

# Загружаем зависимости
RUN cargo fetch --locked -vv

# Собираем зависимости из локального кеша
RUN cargo build --release --locked --offline -vv

# Удаляем временный исходник
RUN rm -rf src

# Копируем настоящий проект
COPY . .

# Собираем настоящий backend
RUN cargo build --release --locked --offline -vv


# =========================
# Финальный образ
# =========================
FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libssl3 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 appuser

WORKDIR /app

COPY --from=builder \
    /app/target/release/gonow-backend \
    /usr/local/bin/gonow-backend

USER appuser

EXPOSE 8080

CMD ["/usr/local/bin/gonow-backend"]