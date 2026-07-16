FROM rust:1.95-bookworm AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && printf 'fn main() {}' > src/main.rs && cargo build --release && rm -rf src
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
RUN useradd --create-home --uid 10001 appuser
COPY --from=builder /app/target/release/gonow-backend /usr/local/bin/gonow-backend
USER appuser
EXPOSE 8080
CMD ["gonow-backend"]
