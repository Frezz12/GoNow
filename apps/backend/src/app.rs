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
    modules::{activities, auth, map_proxy, media, users, weather},
    shared::errors::with_request_id,
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
    paths(auth::register, auth::verify_email, auth::forgot_password, auth::reset_password, auth::login, auth::refresh, auth::logout, users::me, users::update_me, users::public_profile, media::list_profile_photos, media::upload_avatar, media::upload_profile_photo, media::download_profile_photo, media::delete_profile_photo, weather::current, activities::create, activities::map, health),
    components(schemas(auth::RegisterRequest, auth::RegistrationData, auth::VerifyEmailRequest, auth::ForgotPasswordRequest, auth::ResetPasswordRequest, auth::LoginRequest, auth::RefreshRequest, auth::LogoutRequest, auth::AuthData, auth::Tokens, users::UserResponse, users::PublicProfileResponse, users::UpdateProfileRequest, media::ProfilePhotoResponse, media::ProfilePhotosResponse, weather::CurrentWeatherResponse, activities::CreateActivityRequest, activities::MapActivityResponse, activities::ActivityCoordinateResponse, activities::MapViewportResponse, activities::MapActivitiesData, activities::MapActivitiesMeta, activities::MapActivitiesEnvelope, crate::shared::response::ErrorEnvelope)),
    tags((name = "authentication", description = "Registration and session management"), (name = "users", description = "Current user"), (name = "media", description = "Private profile photos"), (name = "weather", description = "Current weather"), (name = "activities", description = "Offline activities and map discovery"))
)]
struct ApiDoc;

pub fn router(state: AppState) -> Router {
    let origins: Vec<HeaderValue> = state.config.cors_allowed_origins.clone();
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
        .route("/api/v1/activities", post(activities::create))
        .route("/api/v1/activities/map", get(activities::map))
        .route("/api/v1/weather/current", get(weather::current))
        .route("/api/v1/map/style", get(map_proxy::style))
        .route("/api/v1/map/planet", get(map_proxy::planet))
        .route("/api/v1/map/resources/{*path}", get(map_proxy::resource))
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
        .layer(DefaultBodyLimit::max(media::MAX_MULTIPART_BODY_BYTES))
        .with_state(state)
}

async fn request_id(mut request: Request, next: Next) -> Response {
    let method = request.method().clone();
    let uri = request.uri().clone();
    let (operation, action) = request_operation(&method, uri.path());
    let started_at = Instant::now();
    let request_id = request
        .headers()
        .get("x-request-id")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| Uuid::parse_str(value).ok())
        .map(|value| value.to_string())
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    request.extensions_mut().insert(request_id.clone());
    let mut response = with_request_id(request_id.clone(), next.run(request)).await;
    if let Ok(value) = request_id.parse() {
        response.headers_mut().insert("x-request-id", value);
    }
    info!(
        operation,
        action,
        method = %method,
        path = %uri.path(),
        status = response.status().as_u16(),
        latency_ms = started_at.elapsed().as_millis(),
        %request_id,
        "HTTP request completed"
    );
    response
}

/// Stable operation names make development logs understandable without memorising URL paths.
fn request_operation(method: &Method, path: &str) -> (&'static str, &'static str) {
    match (method.as_str(), path) {
        ("GET", "/health") => ("system.health", "Проверка сервисов"),
        ("POST", "/api/v1/auth/register") => ("auth.register", "Регистрация"),
        ("POST", "/api/v1/auth/verify-email") => ("auth.verify_email", "Подтверждение email"),
        ("POST", "/api/v1/auth/forgot-password") => {
            ("auth.forgot_password", "Запрос сброса пароля")
        }
        ("POST", "/api/v1/auth/reset-password") => ("auth.reset_password", "Смена пароля"),
        ("POST", "/api/v1/auth/login") => ("auth.login", "Вход"),
        ("POST", "/api/v1/auth/refresh") => ("auth.refresh", "Обновление сессии"),
        ("POST", "/api/v1/auth/logout") => ("auth.logout", "Выход"),
        ("GET", "/api/v1/weather/current") => ("weather.current", "Текущая погода"),
        ("GET", "/api/v1/map/style") => ("map.style", "Стиль карты"),
        ("GET", "/api/v1/map/planet") => ("map.tilejson", "Описание тайлов карты"),
        ("GET", path) if path.starts_with("/api/v1/map/resources/") => {
            ("map.resource", "Ресурс карты")
        }
        ("POST", "/api/v1/activities") => ("activities.create", "Создание активности"),
        ("GET", "/api/v1/activities/map") => ("activities.map", "Получение активностей на карте"),
        ("GET", "/api/v1/users/me") => ("users.me.get", "Получение своего профиля"),
        ("PATCH", "/api/v1/users/me") => ("users.me.update", "Обновление профиля"),
        ("GET", "/api/v1/users/me/photos") => ("media.photos.list", "Список фотографий"),
        ("POST", "/api/v1/users/me/photos") => ("media.photo.upload", "Загрузка фотографии"),
        ("POST", "/api/v1/users/me/avatar") => ("media.avatar.upload", "Загрузка аватара"),
        ("DELETE", path) if path.starts_with("/api/v1/users/me/photos/") => {
            ("media.photo.delete", "Удаление фотографии")
        }
        ("GET", path)
            if path.ends_with("/content") && path.starts_with("/api/v1/users/me/photos/") =>
        {
            ("media.photo.download", "Загрузка содержимого фотографии")
        }
        ("GET", path) if path.starts_with("/api/v1/users/") => {
            ("users.profile.get", "Получение публичного профиля")
        }
        ("GET", "/api/openapi.json") => ("docs.openapi", "OpenAPI-спецификация"),
        (_, path) if path.starts_with("/api/docs") => ("docs.swagger", "Документация API"),
        ("OPTIONS", _) => ("cors.preflight", "Проверка CORS"),
        _ => ("http.request", "HTTP-запрос"),
    }
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
