use std::{sync::Arc, time::Instant};

use axum::{
    Router,
    extract::{DefaultBodyLimit, Request},
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
use tracing::info;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;
use uuid::Uuid;

use crate::{
    config::Config,
    infrastructure::storage::S3ObjectStorage,
    modules::{auth, media, users},
};

#[derive(Clone)]
pub struct AppState {
    pub config: Arc<Config>,
    pub db: PgPool,
    pub redis: ConnectionManager,
    pub object_storage: Option<S3ObjectStorage>,
}

impl AppState {
    pub async fn connect(config: Config) -> Result<Self, String> {
        let object_storage = match &config.object_storage {
            Some(config) => Some(S3ObjectStorage::connect(config).await),
            None => None,
        };
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
            object_storage,
        })
    }
}

#[derive(OpenApi)]
#[openapi(
    paths(auth::register, auth::verify_email, auth::forgot_password, auth::reset_password, auth::login, auth::refresh, auth::logout, users::me, users::update_me, users::public_profile, media::list_profile_photos, media::upload_avatar, media::upload_profile_photo, media::download_profile_photo, media::delete_profile_photo, health),
    components(schemas(auth::RegisterRequest, auth::RegistrationData, auth::VerifyEmailRequest, auth::ForgotPasswordRequest, auth::ResetPasswordRequest, auth::LoginRequest, auth::RefreshRequest, auth::LogoutRequest, auth::AuthData, auth::Tokens, users::UserResponse, users::PublicProfileResponse, users::UpdateProfileRequest, media::ProfilePhotoResponse, media::ProfilePhotosResponse, crate::shared::response::ErrorEnvelope)),
    tags((name = "authentication", description = "Registration and session management"), (name = "users", description = "Current user"), (name = "media", description = "Private profile photos"))
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
        .allow_methods([
            Method::GET,
            Method::POST,
            Method::PATCH,
            Method::DELETE,
            Method::OPTIONS,
        ])
        .allow_headers(tower_http::cors::Any)
        .allow_origin(AllowOrigin::list(origins));
    Router::new()
        .route("/health", get(health))
        .route("/api/v1/auth/register", post(auth::register))
        .route("/api/v1/auth/verify-email", post(auth::verify_email))
        .route("/api/v1/auth/forgot-password", post(auth::forgot_password))
        .route("/api/v1/auth/reset-password", post(auth::reset_password))
        .route("/api/v1/auth/login", post(auth::login))
        .route("/api/v1/auth/refresh", post(auth::refresh))
        .route("/api/v1/auth/logout", post(auth::logout))
        .route("/api/v1/users/me", get(users::me).patch(users::update_me))
        .route("/api/v1/users/{user_id}", get(users::public_profile))
        .route(
            "/api/v1/users/me/photos",
            get(media::list_profile_photos).post(media::upload_profile_photo),
        )
        .route("/api/v1/users/me/avatar", post(media::upload_avatar))
        .route(
            "/api/v1/users/me/photos/{photo_id}",
            axum::routing::delete(media::delete_profile_photo),
        )
        .route(
            "/api/v1/users/me/photos/{photo_id}/content",
            get(media::download_profile_photo),
        )
        .merge(SwaggerUi::new("/api/docs").url("/api/openapi.json", ApiDoc::openapi()))
        .layer(middleware::from_fn(request_id))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .layer(DefaultBodyLimit::max(media::MAX_IMAGE_BYTES))
        .with_state(state)
}

async fn request_id(mut request: Request, next: Next) -> Response {
    let method = request.method().clone();
    let uri = request.uri().clone();
    let started_at = Instant::now();
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
    info!(
        method = %method,
        path = %uri.path(),
        query = ?uri.query(),
        status = response.status().as_u16(),
        latency_ms = started_at.elapsed().as_millis(),
        %request_id,
        "HTTP request completed"
    );
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
