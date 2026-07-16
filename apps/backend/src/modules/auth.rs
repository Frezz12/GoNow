use axum::{
    Json,
    extract::State,
    http::{HeaderMap, StatusCode},
};
use chrono::{DateTime, Duration, Utc};
use rand::Rng;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, Postgres, Transaction};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::{
    app::AppState,
    infrastructure::security::{
        generate_refresh_token, hash_password, issue_access_token, refresh_token_hash,
        verify_password,
    },
    modules::users::{UserResponse, UserRow},
    shared::{errors::AppError, response::ApiResponse},
};

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct DeviceRequest {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct RegisterRequest {
    pub email: String,
    pub password: String,
    pub display_name: String,
    pub device: DeviceRequest,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
    pub device: DeviceRequest,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct LogoutRequest {
    pub refresh_token: String,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct VerifyEmailRequest {
    pub email: String,
    pub code: String,
    pub device: DeviceRequest,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct RegistrationData {
    pub email: String,
    pub verification_required: bool,
    pub expires_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct Tokens {
    pub access_token: String,
    pub refresh_token: String,
    pub access_token_expires_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct AuthData {
    pub user: UserResponse,
    pub tokens: Tokens,
}

#[derive(FromRow)]
struct LoginRow {
    id: Uuid,
    email: String,
    password_hash: String,
    display_name: String,
    status: String,
    email_verified: bool,
    created_at: DateTime<Utc>,
}

impl From<LoginRow> for UserResponse {
    fn from(value: LoginRow) -> Self {
        Self {
            id: value.id,
            email: value.email,
            display_name: value.display_name,
            email_verified: value.email_verified,
            created_at: value.created_at,
        }
    }
}

#[derive(FromRow)]
struct SessionRow {
    id: Uuid,
    user_id: Uuid,
    device_id: String,
    device_name: String,
    platform: String,
    expires_at: DateTime<Utc>,
    revoked_at: Option<DateTime<Utc>>,
}

fn validation_error(
    email: &str,
    password: &str,
    display_name: Option<&str>,
    device: &DeviceRequest,
    password_min_length: usize,
) -> Option<AppError> {
    let mut fields = serde_json::Map::new();
    if !email.contains('@') || email.len() > 254 {
        fields.insert("email".into(), "Введите корректный email".into());
    }
    if password.len() < password_min_length
        || password.len() > 128
        || password.chars().any(char::is_control)
    {
        fields.insert(
            "password".into(),
            format!("Пароль должен содержать от {password_min_length} до 128 символов").into(),
        );
    }
    if let Some(name) = display_name {
        if name.trim().chars().count() < 2 || name.trim().chars().count() > 80 {
            fields.insert(
                "displayName".into(),
                "Имя должно содержать от 2 до 80 символов".into(),
            );
        }
    }
    if device.device_id.trim().is_empty() || device.device_id.len() > 128 {
        fields.insert(
            "device.deviceId".into(),
            "Некорректный идентификатор устройства".into(),
        );
    }
    if device.device_name.trim().is_empty() || device.device_name.len() > 128 {
        fields.insert(
            "device.deviceName".into(),
            "Некорректное имя устройства".into(),
        );
    }
    if device.platform != "ios" && device.platform != "android" && device.platform != "web" {
        fields.insert("device.platform".into(), "Некорректная платформа".into());
    }
    (!fields.is_empty()).then(|| AppError::validation(serde_json::Value::Object(fields)))
}

async fn enforce_rate_limit(state: &AppState, key: String, maximum: i64) -> Result<(), AppError> {
    let mut redis = state.redis.clone();
    let count: i64 = redis
        .incr(&key, 1)
        .await
        .map_err(|_| AppError::service_unavailable())?;
    if count == 1 {
        let _: bool = redis
            .expire(&key, state.config.rate_limit_window_seconds)
            .await
            .map_err(|_| AppError::service_unavailable())?;
    }
    if count > maximum {
        return Err(AppError {
            status: StatusCode::TOO_MANY_REQUESTS,
            code: "RATE_LIMITED",
            message: "Слишком много попыток. Повторите позже".into(),
            fields: None,
        });
    }
    Ok(())
}

fn client_ip(headers: &HeaderMap) -> String {
    headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(',').next())
        .unwrap_or("local")
        .trim()
        .to_owned()
}
fn normalized_email(value: &str) -> String {
    value.trim().to_lowercase()
}

async fn create_session(
    tx: &mut Transaction<'_, Postgres>,
    state: &AppState,
    user_id: Uuid,
    device: &DeviceRequest,
) -> Result<Tokens, AppError> {
    let refresh_token = generate_refresh_token();
    let token_hash = refresh_token_hash(&refresh_token, &state.config.jwt_refresh_secret);
    let expires_at = Utc::now() + Duration::seconds(state.config.jwt_refresh_ttl_seconds);
    sqlx::query("INSERT INTO refresh_sessions (id, user_id, token_hash, device_id, device_name, platform, expires_at) VALUES ($1, $2, $3, $4, $5, $6, $7)")
        .bind(Uuid::new_v4()).bind(user_id).bind(token_hash).bind(device.device_id.trim()).bind(device.device_name.trim()).bind(&device.platform).bind(expires_at)
        .execute(&mut **tx).await.map_err(AppError::internal)?;
    let (access_token, access_token_expires_at) = issue_access_token(
        user_id,
        &state.config.jwt_access_secret,
        state.config.jwt_access_ttl_seconds,
    )?;
    Ok(Tokens {
        access_token,
        refresh_token,
        access_token_expires_at,
    })
}

async fn issue_email_code(
    tx: &mut Transaction<'_, Postgres>, state: &AppState, user_id: Uuid, purpose: &str,
) -> Result<(String, DateTime<Utc>), AppError> {
    let code = format!("{:06}", rand::thread_rng().gen_range(0..1_000_000));
    let expires_at = Utc::now() + Duration::seconds(state.config.email_code_ttl_seconds);
    sqlx::query("DELETE FROM email_codes WHERE user_id = $1 AND purpose = $2 AND consumed_at IS NULL")
        .bind(user_id).bind(purpose).execute(&mut **tx).await.map_err(AppError::internal)?;
    sqlx::query("INSERT INTO email_codes (id, user_id, purpose, code_hash, expires_at) VALUES ($1, $2, $3, $4, $5)")
        .bind(Uuid::new_v4()).bind(user_id).bind(purpose)
        .bind(refresh_token_hash(&code, &state.config.jwt_refresh_secret)).bind(expires_at)
        .execute(&mut **tx).await.map_err(AppError::internal)?;
    Ok((code, expires_at))
}

async fn send_resend_code(state: &AppState, email: &str, code: &str, title: &str) -> Result<(), AppError> {
    let key = state.config.resend_api_key.as_deref().ok_or_else(AppError::service_unavailable)?;
    let from = state.config.resend_from_email.as_deref().ok_or_else(AppError::service_unavailable)?;
    let body = serde_json::json!({
        "from": from, "to": [email], "subject": title,
        "html": format!("<p>Ваш код GoNow: <strong style=\"font-size:24px;letter-spacing:4px\">{code}</strong></p><p>Код действует 10 минут. Никому его не сообщайте.</p>"),
        "text": format!("Ваш код GoNow: {code}. Код действует 10 минут. Никому его не сообщайте.")
    });
    reqwest::Client::new().post("https://api.resend.com/emails")
        .bearer_auth(key).json(&body).send().await
        .map_err(|_| AppError::service_unavailable())?
        .error_for_status().map_err(|_| AppError::service_unavailable())?;
    Ok(())
}

async fn consume_email_code(tx: &mut Transaction<'_, Postgres>, state: &AppState, user_id: Uuid, purpose: &str, code: &str) -> Result<(), AppError> {
    let row: Option<(Uuid, String, DateTime<Utc>, i32)> = sqlx::query_as("SELECT id, code_hash, expires_at, attempts FROM email_codes WHERE user_id = $1 AND purpose = $2 AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1 FOR UPDATE")
        .bind(user_id).bind(purpose).fetch_optional(&mut **tx).await.map_err(AppError::internal)?;
    let Some((id, hash, expires_at, attempts)) = row else { return Err(AppError::unauthorized("INVALID_EMAIL_CODE", "Код недействителен")); };
    if expires_at <= Utc::now() || attempts >= 5 { return Err(AppError::unauthorized("INVALID_EMAIL_CODE", "Код истёк или недействителен")); }
    if refresh_token_hash(code, &state.config.jwt_refresh_secret) != hash {
        sqlx::query("UPDATE email_codes SET attempts = attempts + 1 WHERE id = $1").bind(id).execute(&mut **tx).await.map_err(AppError::internal)?;
        return Err(AppError::unauthorized("INVALID_EMAIL_CODE", "Неверный код"));
    }
    sqlx::query("UPDATE email_codes SET consumed_at = NOW() WHERE id = $1").bind(id).execute(&mut **tx).await.map_err(AppError::internal)?;
    Ok(())
}

#[utoipa::path(post, path = "/api/v1/auth/register", tag = "authentication", request_body = RegisterRequest, responses((status = 201, body = AuthData), (status = 409, description = "Email is already registered"), (status = 422, description = "Validation failed")))]
pub async fn register(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<RegisterRequest>,
) -> Result<(StatusCode, Json<ApiResponse<RegistrationData>>), AppError> {
    let email = normalized_email(&request.email);
    if let Some(error) = validation_error(
        &email,
        &request.password,
        Some(&request.display_name),
        &request.device,
        state.config.password_min_length,
    ) {
        return Err(error);
    }
    enforce_rate_limit(
        &state,
        format!("ratelimit:register:{}", client_ip(&headers)),
        state.config.rate_limit_register_max,
    )
    .await?;
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    let password_hash = hash_password(&request.password)?;
    let user = sqlx::query_as::<_, UserRow>("INSERT INTO users (id, email, password_hash, display_name) VALUES ($1, $2, $3, $4) RETURNING id, email, display_name, status, email_verified, created_at")
        .bind(Uuid::new_v4()).bind(&email).bind(password_hash).bind(request.display_name.trim())
        .fetch_one(&mut *tx).await.map_err(|error| if is_unique_violation(&error) { AppError { status: StatusCode::CONFLICT, code: "EMAIL_ALREADY_EXISTS", message: "Пользователь с таким email уже зарегистрирован".into(), fields: Some(serde_json::json!({"email":"Этот email уже используется"})) } } else { AppError::internal(error) })?;
    let (code, expires_at) = issue_email_code(&mut tx, &state, user.id, "verify_email").await?;
    tx.commit().await.map_err(AppError::internal)?;
    send_resend_code(&state, &email, &code, "Код подтверждения GoNow").await?;
    Ok((
        StatusCode::CREATED,
        Json(ApiResponse::new(RegistrationData {
            email,
            verification_required: true,
            expires_at,
        })),
    ))
}

#[utoipa::path(post, path = "/api/v1/auth/verify-email", tag = "authentication", request_body = VerifyEmailRequest, responses((status = 200, body = AuthData), (status = 401, description = "Invalid email code")))]
pub async fn verify_email(State(state): State<AppState>, Json(request): Json<VerifyEmailRequest>) -> Result<Json<ApiResponse<AuthData>>, AppError> {
    let email = normalized_email(&request.email);
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    let user: Option<UserRow> = sqlx::query_as("SELECT id, email, display_name, status, email_verified, created_at FROM users WHERE email = $1 FOR UPDATE").bind(&email).fetch_optional(&mut *tx).await.map_err(AppError::internal)?;
    let user = user.ok_or_else(|| AppError::unauthorized("INVALID_EMAIL_CODE", "Код недействителен"))?;
    consume_email_code(&mut tx, &state, user.id, "verify_email", &request.code).await?;
    sqlx::query("UPDATE users SET email_verified = TRUE WHERE id = $1").bind(user.id).execute(&mut *tx).await.map_err(AppError::internal)?;
    let tokens = create_session(&mut tx, &state, user.id, &request.device).await?;
    tx.commit().await.map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(AuthData { user: user.into(), tokens })))
}

#[utoipa::path(post, path = "/api/v1/auth/login", tag = "authentication", request_body = LoginRequest, responses((status = 200, body = AuthData), (status = 401, description = "Invalid credentials"), (status = 422, description = "Validation failed")))]
pub async fn login(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<LoginRequest>,
) -> Result<Json<ApiResponse<AuthData>>, AppError> {
    let email = normalized_email(&request.email);
    if let Some(error) = validation_error(
        &email,
        &request.password,
        None,
        &request.device,
        state.config.password_min_length,
    ) {
        return Err(error);
    }
    enforce_rate_limit(
        &state,
        format!("ratelimit:login:{}:{}", client_ip(&headers), email),
        state.config.rate_limit_login_max,
    )
    .await?;
    let user: Option<LoginRow> = sqlx::query_as("SELECT id, email, password_hash, display_name, status, email_verified, created_at FROM users WHERE email = $1").bind(&email).fetch_optional(&state.db).await.map_err(AppError::internal)?;
    let user = user.ok_or_else(invalid_credentials)?;
    if !verify_password(&request.password, &user.password_hash) {
        return Err(invalid_credentials());
    }
    if user.status != "active" {
        return Err(AppError {
            status: StatusCode::FORBIDDEN,
            code: "USER_DISABLED",
            message: "Учётная запись недоступна".into(),
            fields: None,
        });
    }
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    sqlx::query("UPDATE users SET last_login_at = NOW(), updated_at = NOW() WHERE id = $1")
        .bind(user.id)
        .execute(&mut *tx)
        .await
        .map_err(AppError::internal)?;
    let tokens = create_session(&mut tx, &state, user.id, &request.device).await?;
    tx.commit().await.map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(AuthData {
        user: user.into(),
        tokens,
    })))
}

#[utoipa::path(post, path = "/api/v1/auth/refresh", tag = "authentication", request_body = RefreshRequest, responses((status = 200, body = AuthData), (status = 401, description = "Refresh token is invalid")))]
pub async fn refresh(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<RefreshRequest>,
) -> Result<Json<ApiResponse<AuthData>>, AppError> {
    enforce_rate_limit(
        &state,
        format!("ratelimit:refresh:{}", client_ip(&headers)),
        state.config.rate_limit_refresh_max,
    )
    .await?;
    if request.refresh_token.len() < 32 {
        return Err(AppError::unauthorized(
            "INVALID_REFRESH_TOKEN",
            "Недействительный refresh token",
        ));
    }
    let hash = refresh_token_hash(&request.refresh_token, &state.config.jwt_refresh_secret);
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    let session: Option<SessionRow> = sqlx::query_as("SELECT id, user_id, device_id, device_name, platform, expires_at, revoked_at FROM refresh_sessions WHERE token_hash = $1 FOR UPDATE").bind(hash).fetch_optional(&mut *tx).await.map_err(AppError::internal)?;
    let session = session.ok_or_else(|| {
        AppError::unauthorized("INVALID_REFRESH_TOKEN", "Недействительный refresh token")
    })?;
    if session.revoked_at.is_some() {
        return Err(AppError::unauthorized(
            "SESSION_REVOKED",
            "Сессия была завершена",
        ));
    }
    if session.expires_at <= Utc::now() {
        return Err(AppError::unauthorized(
            "INVALID_REFRESH_TOKEN",
            "Срок действия сессии истёк",
        ));
    }
    let user: Option<UserRow> = sqlx::query_as("SELECT id, email, display_name, status, email_verified, created_at FROM users WHERE id = $1").bind(session.user_id).fetch_optional(&mut *tx).await.map_err(AppError::internal)?;
    let user = user.ok_or_else(|| {
        AppError::unauthorized("INVALID_REFRESH_TOKEN", "Недействительная сессия")
    })?;
    if user.status != "active" {
        return Err(AppError {
            status: StatusCode::FORBIDDEN,
            code: "USER_DISABLED",
            message: "Учётная запись недоступна".into(),
            fields: None,
        });
    }
    sqlx::query(
        "UPDATE refresh_sessions SET revoked_at = NOW(), last_used_at = NOW() WHERE id = $1",
    )
    .bind(session.id)
    .execute(&mut *tx)
    .await
    .map_err(AppError::internal)?;
    let device = DeviceRequest {
        device_id: session.device_id,
        device_name: session.device_name,
        platform: session.platform,
    };
    let tokens = create_session(&mut tx, &state, user.id, &device).await?;
    tx.commit().await.map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(AuthData {
        user: user.into(),
        tokens,
    })))
}

#[utoipa::path(post, path = "/api/v1/auth/logout", tag = "authentication", request_body = LogoutRequest, responses((status = 200, description = "Session revoked")))]
pub async fn logout(
    State(state): State<AppState>,
    Json(request): Json<LogoutRequest>,
) -> Result<Json<ApiResponse<serde_json::Value>>, AppError> {
    let hash = refresh_token_hash(&request.refresh_token, &state.config.jwt_refresh_secret);
    sqlx::query("UPDATE refresh_sessions SET revoked_at = COALESCE(revoked_at, NOW()), last_used_at = NOW() WHERE token_hash = $1").bind(hash).execute(&state.db).await.map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(serde_json::json!({}))))
}

fn invalid_credentials() -> AppError {
    AppError::unauthorized("INVALID_CREDENTIALS", "Неверный email или пароль")
}
fn is_unique_violation(error: &sqlx::Error) -> bool {
    matches!(error, sqlx::Error::Database(database_error) if database_error.code().as_deref() == Some("23505"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn device() -> DeviceRequest {
        DeviceRequest {
            device_id: "test-device".into(),
            device_name: "iPhone".into(),
            platform: "ios".into(),
        }
    }

    #[test]
    fn registration_validation_rejects_invalid_email_and_short_password() {
        let error = validation_error("not-an-email", "short", Some("A"), &device(), 8)
            .expect("validation error");
        let fields = error.fields.expect("field errors");
        assert!(fields.get("email").is_some());
        assert!(fields.get("password").is_some());
        assert!(fields.get("displayName").is_some());
    }

    #[test]
    fn email_normalization_removes_whitespace_and_case() {
        assert_eq!(normalized_email(" User@Example.COM "), "user@example.com");
    }
}
