use std::sync::Arc;

use axum::{
    Router,
    extract::Request,
    http::{HeaderValue, Method},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use redis::aio::ConnectionManager;
use sqlx::{PgPool, postgres::PgPoolOptions};
use tower_http::{
    cors::{AllowOrigin, CorsLayer},
    trace::TraceLayer,
};
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;
use uuid::Uuid;

use crate::{
    config::Config,
    modules::{auth, users},
};

#[derive(Clone)]
pub struct AppState {
    pub config: Arc<Config>,
    pub db: PgPool,
    pub redis: ConnectionManager,
}

impl AppState {
    pub async fn connect(config: Config) -> Result<Self, String> {
        let db = PgPoolOptions::new()
            .max_connections(10)
            .connect(&config.database_url)
            .await
            .map_err(|_| "PostgreSQL is unavailable".to_string())?;
        sqlx::migrate!("./migrations")
            .run(&db)
            .await
            .map_err(|_| "database migrations failed".to_string())?;
        let client = redis::Client::open(config.redis_url.clone())
            .map_err(|_| "invalid REDIS_URL".to_string())?;
        let mut redis = ConnectionManager::new(client)
            .await
            .map_err(|_| "Redis is unavailable".to_string())?;
        redis::cmd("PING")
            .query_async::<String>(&mut redis)
            .await
            .map_err(|_| "Redis is unavailable".to_string())?;
        Ok(Self {
            config: Arc::new(config),
            db,
            redis,
        })
    }
}

#[derive(OpenApi)]
#[openapi(
    paths(auth::register, auth::login, auth::refresh, auth::logout, users::me, health),
    components(schemas(auth::RegisterRequest, auth::LoginRequest, auth::RefreshRequest, auth::LogoutRequest, auth::AuthData, auth::Tokens, users::UserResponse, crate::shared::response::ErrorEnvelope)),
    tags((name = "authentication", description = "Registration and session management"), (name = "users", description = "Current user"))
)]
struct ApiDoc;

pub fn router(state: AppState) -> Router {
    let origins: Vec<HeaderValue> = state
        .config
        .cors_allowed_origins
        .iter()
        .filter_map(|origin| origin.parse().ok())
        .collect();
    let cors = CorsLayer::new()
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers(tower_http::cors::Any)
        .allow_origin(AllowOrigin::list(origins));
    Router::new()
        .route("/health", get(health))
        .route("/api/v1/auth/register", post(auth::register))
        .route("/api/v1/auth/login", post(auth::login))
        .route("/api/v1/auth/refresh", post(auth::refresh))
        .route("/api/v1/auth/logout", post(auth::logout))
        .route("/api/v1/users/me", get(users::me))
        .merge(SwaggerUi::new("/api/docs").url("/api/openapi.json", ApiDoc::openapi()))
        .layer(middleware::from_fn(request_id))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state)
}

async fn request_id(mut request: Request, next: Next) -> Response {
    let request_id = request
        .headers()
        .get("x-request-id")
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned)
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    request.extensions_mut().insert(request_id.clone());
    let mut response = next.run(request).await;
    if !response.headers().contains_key("x-request-id") {
        if let Ok(value) = request_id.parse() {
            response.headers_mut().insert("x-request-id", value);
        }
    }
    response
}

#[utoipa::path(get, path = "/health", responses((status = 200, description = "Dependencies are available"), (status = 503, description = "A dependency is unavailable")))]
async fn health(axum::extract::State(state): axum::extract::State<AppState>) -> Response {
    let postgres_ok = sqlx::query_scalar::<_, i32>("SELECT 1")
        .fetch_one(&state.db)
        .await
        .is_ok();
    let mut redis = state.redis.clone();
    let redis_ok = redis::cmd("PING")
        .query_async::<String>(&mut redis)
        .await
        .is_ok();
    let status = if postgres_ok && redis_ok {
        axum::http::StatusCode::OK
    } else {
        axum::http::StatusCode::SERVICE_UNAVAILABLE
    };
    let services = serde_json::json!({"postgres": if postgres_ok { "ok" } else { "unavailable" }, "redis": if redis_ok { "ok" } else { "unavailable" }});
    (status, axum::Json(serde_json::json!({"status": if status.is_success() { "ok" } else { "degraded" }, "services": services}))).into_response()
}
