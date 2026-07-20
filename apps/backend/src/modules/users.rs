use axum::{
    Json,
    extract::{Query, State},
    http::{HeaderMap, StatusCode},
};
use chrono::{DateTime, Datelike, Duration, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::{
    app::AppState,
    infrastructure::{cache, security::verify_access_token},
    shared::{errors::AppError, response::ApiResponse},
};

#[derive(Clone, Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UserResponse {
    pub id: Uuid,
    pub email: String,
    pub display_name: String,
    pub username: String,
    pub email_verified: bool,
    pub birth_date: Option<NaiveDate>,
    pub city: Option<String>,
    pub occupation: Option<String>,
    pub bio: Option<String>,
    pub interests: Vec<String>,
    pub languages: Vec<String>,
    pub availability: Option<String>,
    pub preferred_group_size: Option<String>,
    pub rating: f64,
    pub relationship_status: Option<String>,
    pub location_label: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub show_distance: bool,
    pub profile_complete: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(FromRow)]
pub(crate) struct UserRow {
    pub id: Uuid,
    pub email: String,
    pub display_name: String,
    pub username: String,
    pub status: String,
    pub email_verified: bool,
    pub birth_date: Option<NaiveDate>,
    pub city: Option<String>,
    pub occupation: Option<String>,
    pub bio: Option<String>,
    pub interests: Vec<String>,
    pub languages: Vec<String>,
    pub availability: Option<String>,
    pub preferred_group_size: Option<String>,
    pub rating: f64,
    pub relationship_status: Option<String>,
    pub location_label: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub show_distance: bool,
    pub created_at: DateTime<Utc>,
}

impl From<UserRow> for UserResponse {
    fn from(value: UserRow) -> Self {
        let profile_complete = value.birth_date.is_some();
        Self {
            id: value.id,
            email: value.email,
            display_name: value.display_name,
            username: value.username,
            email_verified: value.email_verified,
            birth_date: value.birth_date,
            city: value.city,
            occupation: value.occupation,
            bio: value.bio,
            interests: value.interests,
            languages: value.languages,
            availability: value.availability,
            preferred_group_size: value.preferred_group_size,
            rating: value.rating,
            relationship_status: value.relationship_status,
            location_label: value.location_label,
            latitude: value.latitude,
            longitude: value.longitude,
            show_distance: value.show_distance,
            profile_complete,
            created_at: value.created_at,
        }
    }
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UpdateProfileRequest {
    pub display_name: String,
    pub username: String,
    pub birth_date: Option<NaiveDate>,
    pub city: Option<String>,
    pub occupation: Option<String>,
    pub bio: Option<String>,
    pub interests: Vec<String>,
    #[serde(default)]
    pub languages: Vec<String>,
    #[serde(default)]
    pub availability: Option<String>,
    #[serde(default)]
    pub preferred_group_size: Option<String>,
    pub relationship_status: Option<String>,
    pub location_label: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub show_distance: bool,
}

/// The safe, viewer-facing representation of a profile. It intentionally has
/// neither email, address label, nor coordinates.
#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct PublicProfileResponse {
    pub id: Uuid,
    pub display_name: String,
    pub username: String,
    pub age: Option<i32>,
    pub city: Option<String>,
    pub occupation: Option<String>,
    pub relationship_status: Option<String>,
    pub bio: Option<String>,
    pub interests: Vec<String>,
    pub languages: Vec<String>,
    pub availability: Option<String>,
    pub preferred_group_size: Option<String>,
    pub rating: f64,
    pub distance_km: Option<f64>,
}

#[derive(FromRow)]
struct PublicProfileRow {
    id: Uuid,
    display_name: String,
    username: String,
    status: String,
    birth_date: Option<NaiveDate>,
    city: Option<String>,
    occupation: Option<String>,
    relationship_status: Option<String>,
    bio: Option<String>,
    interests: Vec<String>,
    languages: Vec<String>,
    availability: Option<String>,
    preferred_group_size: Option<String>,
    rating: f64,
    latitude: Option<f64>,
    longitude: Option<f64>,
    show_distance: bool,
}

fn rounded_distance_km(
    viewer_latitude: Option<f64>,
    viewer_longitude: Option<f64>,
    profile: &PublicProfileRow,
) -> Option<f64> {
    if !profile.show_distance {
        return None;
    }
    let (from_latitude, from_longitude, to_latitude, to_longitude) = (
        viewer_latitude?,
        viewer_longitude?,
        profile.latitude?,
        profile.longitude?,
    );
    let to_radians = std::f64::consts::PI / 180.0;
    let latitude_delta = (to_latitude - from_latitude) * to_radians;
    let longitude_delta = (to_longitude - from_longitude) * to_radians;
    let a = (latitude_delta / 2.0).sin().powi(2)
        + from_latitude.to_radians().cos()
            * to_latitude.to_radians().cos()
            * (longitude_delta / 2.0).sin().powi(2);
    Some((6_371.0 * 2.0 * a.sqrt().atan2((1.0 - a).sqrt()) * 10.0).round() / 10.0)
}

fn age_from_birth_date(birth_date: Option<NaiveDate>) -> Option<i32> {
    let birth_date = birth_date?;
    let today = Utc::now().date_naive();
    let had_birthday = (today.month(), today.day()) >= (birth_date.month(), birth_date.day());
    Some(today.year() - birth_date.year() - i32::from(!had_birthday))
}

fn clean_optional(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

pub(crate) fn normalized_username(value: &str) -> String {
    value.trim().trim_start_matches('@').to_ascii_lowercase()
}

pub(crate) fn username_validation_message(username: &str) -> Option<&'static str> {
    if !(5..=32).contains(&username.len()) {
        return Some("Username должен содержать от 5 до 32 символов");
    }
    let mut characters = username.chars();
    if !characters
        .next()
        .is_some_and(|value| value.is_ascii_lowercase())
        || !characters
            .all(|value| value.is_ascii_lowercase() || value.is_ascii_digit() || value == '_')
    {
        return Some(
            "Используйте латинские буквы, цифры и знак подчёркивания; первый символ — буква",
        );
    }
    if matches!(
        username,
        "admin" | "administrator" | "support" | "gonow" | "official" | "system"
    ) {
        return Some("Этот username зарезервирован");
    }
    None
}

#[derive(Debug, Deserialize)]
pub struct UsernameAvailabilityQuery {
    pub username: String,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UsernameAvailabilityResponse {
    pub username: String,
    pub available: bool,
    pub message: Option<String>,
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
    let username = normalized_username(&request.username);
    if let Some(message) = username_validation_message(&username) {
        fields.insert("username".into(), message.into());
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
    if request.languages.len() > 8
        || request.languages.iter().any(|value| {
            let length = value.trim().chars().count();
            !(2..=32).contains(&length)
        })
    {
        fields.insert(
            "languages".into(),
            "Добавьте до 8 языков по 2–32 символа".into(),
        );
    }
    if request
        .availability
        .as_deref()
        .map(str::trim)
        .is_some_and(|value| value.chars().count() > 120)
    {
        fields.insert(
            "availability".into(),
            "Описание свободного времени не должно быть длиннее 120 символов".into(),
        );
    }
    if request
        .preferred_group_size
        .as_deref()
        .is_some_and(|value| !matches!(value, "oneToOne" | "smallGroup" | "largeGroup" | "any"))
    {
        fields.insert(
            "preferredGroupSize".into(),
            "Выберите допустимый формат компании".into(),
        );
    }
    if request
        .relationship_status
        .as_deref()
        .map(str::trim)
        .is_some_and(|value| value.chars().count() > 64)
    {
        fields.insert(
            "relationshipStatus".into(),
            "Семейное положение не должно быть длиннее 64 символов".into(),
        );
    }
    if request
        .location_label
        .as_deref()
        .map(str::trim)
        .is_some_and(|value| value.chars().count() > 160)
    {
        fields.insert(
            "locationLabel".into(),
            "Название места не должно быть длиннее 160 символов".into(),
        );
    }
    if request.latitude.is_some() != request.longitude.is_some()
        || request
            .latitude
            .is_some_and(|value| !(-90.0..=90.0).contains(&value))
        || request
            .longitude
            .is_some_and(|value| !(-180.0..=180.0).contains(&value))
    {
        fields.insert(
            "location".into(),
            "Укажите корректные координаты места".into(),
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

pub(crate) fn authenticated_user_id(
    headers: &HeaderMap,
    state: &AppState,
) -> Result<Uuid, AppError> {
    let token = headers
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .ok_or_else(|| AppError::unauthorized("UNAUTHORIZED", "Требуется авторизация"))?;
    verify_access_token(token, &state.config.jwt_access_secret)
}

pub(crate) async fn active_user_id(
    headers: &HeaderMap,
    state: &AppState,
) -> Result<Uuid, AppError> {
    let user_id = authenticated_user_id(headers, state)?;
    let cache_key = format!("cache:user-status:v1:{user_id}");
    let status = if let Some(cached) = cache::get_json::<String>(state, &cache_key).await {
        (cached != "missing").then_some(cached)
    } else {
        let status: Option<String> = sqlx::query_scalar("SELECT status FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_optional(&state.db)
            .await
            .map_err(AppError::internal)?;
        cache::set_json(
            state,
            &cache_key,
            status.as_deref().unwrap_or("missing"),
            state.config.redis_user_status_cache_ttl_seconds,
        )
        .await;
        status
    };
    match status.as_deref() {
        Some("active") => Ok(user_id),
        Some(_) => Err(AppError {
            status: StatusCode::FORBIDDEN,
            code: "USER_DISABLED",
            message: "Учётная запись недоступна".into(),
            fields: None,
        }),
        None => Err(AppError::unauthorized(
            "UNAUTHORIZED",
            "Пользователь не найден",
        )),
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
    let user_id = authenticated_user_id(&headers, &state)?;
    let user: Option<UserRow> = sqlx::query_as("SELECT id, email, display_name, username, status, email_verified, birth_date, city, occupation, bio, interests, languages, availability, preferred_group_size, rating, relationship_status, location_label, latitude, longitude, show_distance, created_at FROM users WHERE id = $1")
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
    let user_id = active_user_id(&headers, &state).await?;
    let username = normalized_username(&request.username);
    let interests = request
        .interests
        .iter()
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();
    let languages = request
        .languages
        .iter()
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();
    let user: Option<UserRow> = sqlx::query_as("UPDATE users SET display_name = $2, username = $3, birth_date = $4, city = $5, occupation = $6, bio = $7, interests = $8, languages = $9, availability = $10, preferred_group_size = $11, relationship_status = $12, location_label = $13, latitude = $14, longitude = $15, show_distance = $16, updated_at = NOW() WHERE id = $1 AND status = 'active' RETURNING id, email, display_name, username, status, email_verified, birth_date, city, occupation, bio, interests, languages, availability, preferred_group_size, rating, relationship_status, location_label, latitude, longitude, show_distance, created_at")
        .bind(user_id)
        .bind(request.display_name.trim())
        .bind(username)
        .bind(request.birth_date)
        .bind(clean_optional(request.city))
        .bind(clean_optional(request.occupation))
        .bind(clean_optional(request.bio))
        .bind(interests)
        .bind(languages)
        .bind(clean_optional(request.availability))
        .bind(clean_optional(request.preferred_group_size))
        .bind(clean_optional(request.relationship_status))
        .bind(clean_optional(request.location_label))
        .bind(request.latitude)
        .bind(request.longitude)
        .bind(request.show_distance)
        .fetch_optional(&state.db)
        .await
        .map_err(|error| {
            if error
                .as_database_error()
                .and_then(|error| error.constraint())
                == Some("users_username_unique_idx")
            {
                AppError {
                    status: StatusCode::CONFLICT,
                    code: "USERNAME_TAKEN",
                    message: "Этот username уже занят".into(),
                    fields: Some(serde_json::json!({"username": "Этот username уже занят"})),
                }
            } else {
                AppError::internal(error)
            }
        })?;
    let user =
        user.ok_or_else(|| AppError::unauthorized("UNAUTHORIZED", "Пользователь не найден"))?;
    Ok(Json(ApiResponse::new(UserResponse::from(user))))
}

#[utoipa::path(
    get, path = "/api/v1/users/username-availability", tag = "users",
    params(("username" = String, Query, description = "Username with or without @")),
    responses((status = 200, body = UsernameAvailabilityResponse), (status = 401, description = "An optional access token was provided but is invalid or expired"))
)]
pub async fn username_availability(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<UsernameAvailabilityQuery>,
) -> Result<Json<ApiResponse<UsernameAvailabilityResponse>>, AppError> {
    let user_id = if headers.get("authorization").is_some() {
        Some(authenticated_user_id(&headers, &state)?)
    } else {
        None
    };
    let username = normalized_username(&query.username);
    if let Some(message) = username_validation_message(&username) {
        return Ok(Json(ApiResponse::new(UsernameAvailabilityResponse {
            username,
            available: false,
            message: Some(message.into()),
        })));
    }
    let owner: Option<Uuid> = sqlx::query_scalar("SELECT id FROM users WHERE username = $1")
        .bind(&username)
        .fetch_optional(&state.db)
        .await
        .map_err(AppError::internal)?;
    let available = owner.is_none_or(|owner| Some(owner) == user_id);
    Ok(Json(ApiResponse::new(UsernameAvailabilityResponse {
        username,
        available,
        message: (!available).then(|| "Этот username уже занят".into()),
    })))
}

#[utoipa::path(
    get, path = "/api/v1/users/{user_id}", tag = "users", security(("bearer_auth" = [])),
    params(("user_id" = Uuid, Path, description = "Profile owner ID")),
    responses((status = 200, body = PublicProfileResponse), (status = 404, description = "Profile not found"), (status = 401, description = "Access token is invalid or expired"))
)]
pub async fn public_profile(
    State(state): State<AppState>,
    headers: HeaderMap,
    axum::extract::Path(user_id): axum::extract::Path<Uuid>,
) -> Result<Json<ApiResponse<PublicProfileResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let viewer_location: Option<(Option<f64>, Option<f64>)> =
        sqlx::query_as("SELECT latitude, longitude FROM users WHERE id = $1 AND status = 'active'")
            .bind(viewer_id)
            .fetch_optional(&state.db)
            .await
            .map_err(AppError::internal)?;
    let (viewer_latitude, viewer_longitude) = viewer_location
        .ok_or_else(|| AppError::unauthorized("UNAUTHORIZED", "Пользователь не найден"))?;
    let profile: Option<PublicProfileRow> = sqlx::query_as(
        "SELECT id, display_name, username, status, birth_date, city, occupation, relationship_status, bio, interests, languages, availability, preferred_group_size, rating, latitude, longitude, show_distance FROM users WHERE id = $1",
    )
    .bind(user_id)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?;
    let profile = profile
        .filter(|profile| profile.status == "active")
        .ok_or_else(|| AppError {
            status: StatusCode::NOT_FOUND,
            code: "PROFILE_NOT_FOUND",
            message: "Профиль не найден".into(),
            fields: None,
        })?;
    let distance_km = rounded_distance_km(viewer_latitude, viewer_longitude, &profile);
    Ok(Json(ApiResponse::new(PublicProfileResponse {
        id: profile.id,
        display_name: profile.display_name,
        username: profile.username,
        age: age_from_birth_date(profile.birth_date),
        city: profile.city,
        occupation: profile.occupation,
        relationship_status: profile.relationship_status,
        bio: profile.bio,
        interests: profile.interests,
        languages: profile.languages,
        availability: profile.availability,
        preferred_group_size: profile.preferred_group_size,
        rating: profile.rating,
        distance_km,
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_request() -> UpdateProfileRequest {
        UpdateProfileRequest {
            display_name: "Николай".into(),
            username: "nikolay_test".into(),
            birth_date: Some(Utc::now().date_naive() - Duration::days(25 * 365)),
            city: Some("Москва".into()),
            occupation: Some("Дизайнер".into()),
            bio: Some("Люблю прогулки и новые знакомства".into()),
            interests: vec!["Прогулки".into()],
            languages: vec!["Русский".into()],
            availability: Some("Будни после 19:00".into()),
            preferred_group_size: Some("smallGroup".into()),
            relationship_status: None,
            location_label: None,
            latitude: None,
            longitude: None,
            show_distance: true,
        }
    }

    #[test]
    fn accepts_compatibility_profile_fields() {
        assert!(profile_validation_error(&valid_request()).is_none());
    }

    #[test]
    fn username_normalization_and_validation_are_stable() {
        assert_eq!(normalized_username(" @Nikolay_26 "), "nikolay_26");
        assert!(username_validation_message("nikolay_26").is_none());
        assert!(username_validation_message("26nikolay").is_some());
        assert!(username_validation_message("николай").is_some());
        assert!(username_validation_message("admin").is_some());
    }

    #[test]
    fn rejects_unknown_preferred_group_size() {
        let mut request = valid_request();
        request.preferred_group_size = Some("crowd".into());

        let error = profile_validation_error(&request).expect("validation must fail");
        assert_eq!(error.code, "VALIDATION_ERROR");
        assert!(
            error
                .fields
                .expect("fields")
                .get("preferredGroupSize")
                .is_some()
        );
    }

    #[test]
    fn rejects_too_many_languages() {
        let mut request = valid_request();
        request.languages = (0..9).map(|index| format!("Язык {index}")).collect();

        let error = profile_validation_error(&request).expect("validation must fail");
        assert!(error.fields.expect("fields").get("languages").is_some());
    }
}
