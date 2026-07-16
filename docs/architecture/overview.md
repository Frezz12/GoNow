# Architecture

Backend — модульный Rust monolith: Axum API → auth/users modules → SQLx PostgreSQL и Redis. PostgreSQL хранит пользователей и refresh-сессии; Redis используется для rate limits. OpenAPI на `/api/openapi.json` — общий контракт клиентов.

SwiftUI следует цепочке View → AppState → AuthRepository → APIClient/KeychainStore. `APIClient` является actor и объединяет одновременные обновления токена.
