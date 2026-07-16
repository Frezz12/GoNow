use axum::{Json, extract::State, http::HeaderMap};
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::FromRow;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::{
    app::AppState,
    infrastructure::security::verify_access_token,
    shared::{errors::AppError, response::ApiResponse},
};

#[derive(Clone, Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UserResponse {
    pub id: Uuid,
    pub email: String,
    pub display_name: String,
    pub email_verified: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(FromRow)]
pub(crate) struct UserRow {
    pub id: Uuid,
    pub email: String,
    pub display_name: String,
    pub status: String,
    pub email_verified: bool,
    pub created_at: DateTime<Utc>,
}

impl From<UserRow> for UserResponse {
    fn from(value: UserRow) -> Self {
        Self {
            id: value.id,
            email: value.email,
            display_name: value.display_name,
            email_verified: value.email_verified,
            created_at: value.created_at,
        }
    }
}

#[utoipa::path(
    get, path = "/api/v1/users/me", tag = "users", security(("bearer_auth" = [])),
    responses((status = 200, body = UserResponse), (status = 401, description = "Access token is invalid or expired"))
)]
pub async fn me(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<UserResponse>>, AppError> {
    let token = headers
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .ok_or_else(|| AppError::unauthorized("UNAUTHORIZED", "Требуется авторизация"))?;
    let user_id = verify_access_token(token, &state.config.jwt_access_secret)?;
    let user: Option<UserRow> = sqlx::query_as("SELECT id, email, display_name, status, email_verified, created_at FROM users WHERE id = $1")
        .bind(user_id).fetch_optional(&state.db).await.map_err(AppError::internal)?;
    let user =
        user.ok_or_else(|| AppError::unauthorized("UNAUTHORIZED", "Пользователь не найден"))?;
    if user.status != "active" {
        return Err(AppError {
            status: axum::http::StatusCode::FORBIDDEN,
            code: "USER_DISABLED",
            message: "Учётная запись недоступна".into(),
            fields: None,
        });
    }
    Ok(Json(ApiResponse::new(UserResponse::from(user))))
}
