use axum::{
    Json,
    extract::State,
    http::{HeaderMap, StatusCode},
};
use chrono::{DateTime, Duration, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
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
    pub birth_date: Option<NaiveDate>,
    pub city: Option<String>,
    pub occupation: Option<String>,
    pub bio: Option<String>,
    pub interests: Vec<String>,
    pub rating: f64,
    pub profile_complete: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(FromRow)]
pub(crate) struct UserRow {
    pub id: Uuid,
    pub email: String,
    pub display_name: String,
    pub status: String,
    pub email_verified: bool,
    pub birth_date: Option<NaiveDate>,
    pub city: Option<String>,
    pub occupation: Option<String>,
    pub bio: Option<String>,
    pub interests: Vec<String>,
    pub rating: f64,
    pub created_at: DateTime<Utc>,
}

impl From<UserRow> for UserResponse {
    fn from(value: UserRow) -> Self {
        let profile_complete = value.birth_date.is_some();
        Self {
            id: value.id,
            email: value.email,
            display_name: value.display_name,
            email_verified: value.email_verified,
            birth_date: value.birth_date,
            city: value.city,
            occupation: value.occupation,
            bio: value.bio,
            interests: value.interests,
            rating: value.rating,
            profile_complete,
            created_at: value.created_at,
        }
    }
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UpdateProfileRequest {
    pub display_name: String,
    pub birth_date: Option<NaiveDate>,
    pub city: Option<String>,
    pub occupation: Option<String>,
    pub bio: Option<String>,
    pub interests: Vec<String>,
}

fn clean_optional(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

fn profile_validation_error(request: &UpdateProfileRequest) -> Option<AppError> {
    let mut fields = serde_json::Map::new();
    let name_length = request.display_name.trim().chars().count();
    if !(2..=80).contains(&name_length) {
        fields.insert(
            "displayName".into(),
            "Имя должно содержать от 2 до 80 символов".into(),
        );
    }
    if request
        .city
        .as_deref()
        .map(str::trim)
        .is_some_and(|value| value.chars().count() > 80)
    {
        fields.insert(
            "city".into(),
            "Город не должен быть длиннее 80 символов".into(),
        );
    }
    if request
        .occupation
        .as_deref()
        .map(str::trim)
        .is_some_and(|value| value.chars().count() > 100)
    {
        fields.insert(
            "occupation".into(),
            "Занятие не должно быть длиннее 100 символов".into(),
        );
    }
    if request
        .bio
        .as_deref()
        .map(str::trim)
        .is_some_and(|value| value.chars().count() > 500)
    {
        fields.insert(
            "bio".into(),
            "Расскажите о себе максимум в 500 символах".into(),
        );
    }
    if request.interests.len() > 12
        || request.interests.iter().any(|value| {
            let length = value.trim().chars().count();
            !(2..=32).contains(&length)
        })
    {
        fields.insert(
            "interests".into(),
            "Добавьте до 12 интересов по 2–32 символа".into(),
        );
    }
    if request.birth_date.is_none() {
        fields.insert(
            "birthDate".into(),
            "Укажите дату рождения, чтобы участвовать в активностях".into(),
        );
    } else if let Some(birth_date) = request.birth_date {
        let today = Utc::now().date_naive();
        if birth_date > today || birth_date < today - Duration::days(120 * 365) {
            fields.insert(
                "birthDate".into(),
                "Укажите корректную дату рождения".into(),
            );
        }
    }
    (!fields.is_empty()).then(|| AppError::validation(serde_json::Value::Object(fields)))
}

fn authenticated_user_id(headers: &HeaderMap, state: &AppState) -> Result<Uuid, AppError> {
    let token = headers
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .ok_or_else(|| AppError::unauthorized("UNAUTHORIZED", "Требуется авторизация"))?;
    verify_access_token(token, &state.config.jwt_access_secret)
}

#[utoipa::path(
    get, path = "/api/v1/users/me", tag = "users", security(("bearer_auth" = [])),
    responses((status = 200, body = UserResponse), (status = 401, description = "Access token is invalid or expired"))
)]
pub async fn me(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<UserResponse>>, AppError> {
    let user_id = authenticated_user_id(&headers, &state)?;
    let user: Option<UserRow> = sqlx::query_as("SELECT id, email, display_name, status, email_verified, birth_date, city, occupation, bio, interests, rating, created_at FROM users WHERE id = $1")
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

#[utoipa::path(
    patch, path = "/api/v1/users/me", tag = "users", security(("bearer_auth" = [])), request_body = UpdateProfileRequest,
    responses((status = 200, body = UserResponse), (status = 401, description = "Access token is invalid or expired"), (status = 422, description = "Validation failed"))
)]
pub async fn update_me(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<UpdateProfileRequest>,
) -> Result<Json<ApiResponse<UserResponse>>, AppError> {
    if let Some(error) = profile_validation_error(&request) {
        return Err(error);
    }
    let user_id = authenticated_user_id(&headers, &state)?;
    let interests = request
        .interests
        .iter()
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();
    let user: Option<UserRow> = sqlx::query_as("UPDATE users SET display_name = $2, birth_date = $3, city = $4, occupation = $5, bio = $6, interests = $7, updated_at = NOW() WHERE id = $1 RETURNING id, email, display_name, status, email_verified, birth_date, city, occupation, bio, interests, rating, created_at")
        .bind(user_id)
        .bind(request.display_name.trim())
        .bind(request.birth_date)
        .bind(clean_optional(request.city))
        .bind(clean_optional(request.occupation))
        .bind(clean_optional(request.bio))
        .bind(interests)
        .fetch_optional(&state.db)
        .await
        .map_err(AppError::internal)?;
    let user =
        user.ok_or_else(|| AppError::unauthorized("UNAUTHORIZED", "Пользователь не найден"))?;
    if user.status != "active" {
        return Err(AppError {
            status: StatusCode::FORBIDDEN,
            code: "USER_DISABLED",
            message: "Учётная запись недоступна".into(),
            fields: None,
        });
    }
    Ok(Json(ApiResponse::new(UserResponse::from(user))))
}
