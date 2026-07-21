FROM rust:1.95-bookworm AS builder

WORKDIR /app

ENV CARGO_TERM_COLOR=always
ENV CARGO_HTTP_MULTIPLEXING=false
ENV CARGO_HTTP_TIMEOUT=120
ENV CARGO_NET_RETRY=10

COPY Cargo.toml Cargo.lock ./
COPY .cargo/config.toml .cargo/config.toml

RUN mkdir -p src \
    && printf 'fn main() {}\n' > src/main.rs

RUN cargo fetch --locked -vv

RUN cargo build --release --locked -vv

RUN rm -rf src

COPY . .

RUN touch src/main.rs \
    && cargo build --release --locked -vv


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