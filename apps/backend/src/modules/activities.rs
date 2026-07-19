use axum::{
    Json,
    extract::{Query, State},
    http::{HeaderMap, StatusCode},
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, Postgres, QueryBuilder};
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

use crate::{
    app::AppState,
    modules::users::active_user_id,
    shared::{errors::AppError, response::ApiResponse},
};

const CATEGORIES: [&str; 9] = [
    "sport",
    "walking",
    "travel",
    "music",
    "games",
    "help",
    "education",
    "animals",
    "other",
];
const MAX_PARTICIPANT_LIMIT: i32 = 100_000;
const MAX_MAP_ZOOM: f64 = 24.0;

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CreateActivityRequest {
    pub title: String,
    pub category: String,
    pub latitude: f64,
    pub longitude: f64,
    pub starts_at: Option<DateTime<Utc>>,
    pub participant_limit: Option<i32>,
}

#[derive(Debug, Deserialize, IntoParams)]
#[serde(rename_all = "camelCase")]
pub struct MapActivitiesQuery {
    pub south: f64,
    pub west: f64,
    pub north: f64,
    pub east: f64,
    pub zoom: f64,
    /// Comma-separated category identifiers.
    pub categories: Option<String>,
    pub starts_from: Option<DateTime<Utc>>,
    pub starts_to: Option<DateTime<Utc>>,
    pub only_available: Option<bool>,
    pub limit: Option<i64>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ActivityCoordinateResponse {
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct MapActivityResponse {
    pub id: Uuid,
    pub title: String,
    pub category: String,
    pub coordinate: ActivityCoordinateResponse,
    pub starts_at: DateTime<Utc>,
    pub participant_count: i32,
    pub participant_limit: Option<i32>,
    pub distance_meters: Option<f64>,
    pub image_url: Option<String>,
    pub is_joined: bool,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct MapViewportResponse {
    pub south: f64,
    pub west: f64,
    pub north: f64,
    pub east: f64,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct MapActivitiesData {
    pub activities: Vec<MapActivityResponse>,
    pub viewport: MapViewportResponse,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct MapActivitiesMeta {
    pub count: usize,
    pub truncated: bool,
    pub next_cursor: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct MapActivitiesEnvelope {
    pub data: MapActivitiesData,
    pub meta: MapActivitiesMeta,
}

#[derive(Debug, FromRow)]
struct ActivityRow {
    id: Uuid,
    creator_id: Uuid,
    title: String,
    category: String,
    latitude: f64,
    longitude: f64,
    starts_at: DateTime<Utc>,
    participant_limit: Option<i32>,
}

impl ActivityRow {
    fn response(self, viewer_id: Uuid) -> MapActivityResponse {
        MapActivityResponse {
            id: self.id,
            title: self.title,
            category: self.category,
            coordinate: ActivityCoordinateResponse {
                latitude: self.latitude,
                longitude: self.longitude,
            },
            starts_at: self.starts_at,
            participant_count: 1,
            participant_limit: self.participant_limit,
            distance_meters: None,
            image_url: None,
            is_joined: self.creator_id == viewer_id,
        }
    }
}

fn validate_coordinates(latitude: f64, longitude: f64) -> bool {
    latitude.is_finite()
        && longitude.is_finite()
        && (-90.0..=90.0).contains(&latitude)
        && (-180.0..=180.0).contains(&longitude)
}

fn validation_error(request: &CreateActivityRequest) -> Option<AppError> {
    let mut fields = serde_json::Map::new();
    let title_length = request.title.trim().chars().count();
    if !(2..=120).contains(&title_length) || request.title.chars().any(char::is_control) {
        fields.insert(
            "title".into(),
            "Название должно содержать от 2 до 120 символов".into(),
        );
    }
    if !CATEGORIES.contains(&request.category.as_str()) {
        fields.insert("category".into(), "Неизвестная категория активности".into());
    }
    if !validate_coordinates(request.latitude, request.longitude) {
        fields.insert("location".into(), "Укажите корректную геопозицию".into());
    }
    if request
        .participant_limit
        .is_some_and(|value| !(1..=MAX_PARTICIPANT_LIMIT).contains(&value))
    {
        fields.insert(
            "participantLimit".into(),
            format!("Количество участников должно быть от 1 до {MAX_PARTICIPANT_LIMIT}").into(),
        );
    }
    (!fields.is_empty()).then(|| AppError::validation(serde_json::Value::Object(fields)))
}

fn validate_map_query(query: &MapActivitiesQuery) -> Result<Vec<String>, AppError> {
    let bounds_are_valid = query.south.is_finite()
        && query.north.is_finite()
        && query.west.is_finite()
        && query.east.is_finite()
        && (-90.0..=90.0).contains(&query.south)
        && (-90.0..=90.0).contains(&query.north)
        && (-180.0..=180.0).contains(&query.west)
        && (-180.0..=180.0).contains(&query.east)
        && query.south <= query.north
        && query.zoom.is_finite()
        && (0.0..=MAX_MAP_ZOOM).contains(&query.zoom);
    if !bounds_are_valid {
        return Err(AppError::validation(serde_json::json!({
            "viewport": "Укажите корректные границы карты"
        })));
    }
    if query
        .starts_from
        .zip(query.starts_to)
        .is_some_and(|(from, to)| from > to)
    {
        return Err(AppError::validation(serde_json::json!({
            "startsTo": "Конец временного интервала должен быть позже начала"
        })));
    }
    if query
        .limit
        .is_some_and(|limit| !(1..=1_000).contains(&limit))
    {
        return Err(AppError::validation(serde_json::json!({
            "limit": "Лимит должен быть от 1 до 1000"
        })));
    }
    let mut categories = query
        .categories
        .as_deref()
        .unwrap_or_default()
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .collect::<Vec<_>>();
    categories.sort_unstable();
    categories.dedup();
    if categories
        .iter()
        .any(|value| !CATEGORIES.contains(&value.as_str()))
    {
        return Err(AppError::validation(serde_json::json!({
            "categories": "Одна или несколько категорий неизвестны"
        })));
    }
    Ok(categories)
}

#[utoipa::path(
    post,
    path = "/api/v1/activities",
    tag = "activities",
    security(("bearer_auth" = [])),
    request_body = CreateActivityRequest,
    responses(
        (status = 201, body = MapActivityResponse, description = "Activity created"),
        (status = 401, description = "Access token is invalid or expired"),
        (status = 422, description = "Validation failed")
    )
)]
pub async fn create(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<CreateActivityRequest>,
) -> Result<(StatusCode, Json<ApiResponse<MapActivityResponse>>), AppError> {
    if let Some(error) = validation_error(&request) {
        return Err(error);
    }
    let viewer_id = active_user_id(&headers, &state).await?;
    let row: ActivityRow = sqlx::query_as(
        "INSERT INTO activities (id, creator_id, title, category, latitude, longitude, starts_at, participant_limit) VALUES ($1, $2, $3, $4, $5, $6, COALESCE($7, NOW()), $8) RETURNING id, creator_id, title, category, latitude, longitude, starts_at, participant_limit",
    )
    .bind(Uuid::new_v4())
    .bind(viewer_id)
    .bind(request.title.trim())
    .bind(request.category)
    .bind(request.latitude)
    .bind(request.longitude)
    .bind(request.starts_at)
    .bind(request.participant_limit)
    .fetch_one(&state.db)
    .await
    .map_err(AppError::internal)?;
    Ok((
        StatusCode::CREATED,
        Json(ApiResponse::new(row.response(viewer_id))),
    ))
}

#[utoipa::path(
    get,
    path = "/api/v1/activities/map",
    tag = "activities",
    security(("bearer_auth" = [])),
    params(MapActivitiesQuery),
    responses(
        (status = 200, body = MapActivitiesEnvelope, description = "Activities inside the visible map bounds"),
        (status = 401, description = "Access token is invalid or expired"),
        (status = 422, description = "Viewport or filters are invalid")
    )
)]
pub async fn map(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<MapActivitiesQuery>,
) -> Result<Json<MapActivitiesEnvelope>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let categories = validate_map_query(&query)?;
    let requested_limit = query.limit.unwrap_or(500);
    let fetch_limit = requested_limit + 1;

    let mut builder = QueryBuilder::<Postgres>::new(
        "SELECT id, creator_id, title, category, latitude, longitude, starts_at, participant_limit FROM activities WHERE status = 'published' AND latitude BETWEEN ",
    );
    builder
        .push_bind(query.south)
        .push(" AND ")
        .push_bind(query.north);
    if query.west <= query.east {
        builder
            .push(" AND longitude BETWEEN ")
            .push_bind(query.west)
            .push(" AND ")
            .push_bind(query.east);
    } else {
        builder
            .push(" AND (longitude >= ")
            .push_bind(query.west)
            .push(" OR longitude <= ")
            .push_bind(query.east)
            .push(")");
    }
    if let Some(starts_from) = query.starts_from {
        builder.push(" AND starts_at >= ").push_bind(starts_from);
    }
    if let Some(starts_to) = query.starts_to {
        builder.push(" AND starts_at <= ").push_bind(starts_to);
    }
    if !categories.is_empty() {
        builder
            .push(" AND category = ANY(")
            .push_bind(categories)
            .push(")");
    }
    if query.only_available.unwrap_or(false) {
        builder.push(" AND (participant_limit IS NULL OR participant_limit > 1)");
    }
    builder
        .push(" ORDER BY starts_at ASC, id ASC LIMIT ")
        .push_bind(fetch_limit);

    let mut rows: Vec<ActivityRow> = builder
        .build_query_as()
        .fetch_all(&state.db)
        .await
        .map_err(AppError::internal)?;
    let truncated = rows.len() as i64 > requested_limit;
    if truncated {
        rows.truncate(requested_limit as usize);
    }
    let activities = rows
        .into_iter()
        .map(|row| row.response(viewer_id))
        .collect::<Vec<_>>();
    Ok(Json(MapActivitiesEnvelope {
        meta: MapActivitiesMeta {
            count: activities.len(),
            truncated,
            next_cursor: None,
        },
        data: MapActivitiesData {
            activities,
            viewport: MapViewportResponse {
                south: query.south,
                west: query.west,
                north: query.north,
                east: query.east,
            },
        },
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_coordinates() {
        assert!(validate_coordinates(55.7558, 37.6173));
        assert!(!validate_coordinates(91.0, 37.6173));
        assert!(!validate_coordinates(55.7558, f64::NAN));
    }

    #[test]
    fn rejects_unknown_category() {
        let request = CreateActivityRequest {
            title: "Прогулка".into(),
            category: "unknown".into(),
            latitude: 55.7558,
            longitude: 37.6173,
            starts_at: None,
            participant_limit: None,
        };
        assert!(validation_error(&request).is_some());
    }

    #[test]
    fn rejects_invalid_map_ranges_and_limits() {
        let query = MapActivitiesQuery {
            south: 55.0,
            west: 37.0,
            north: 56.0,
            east: 38.0,
            zoom: 25.0,
            categories: None,
            starts_from: Some(Utc::now()),
            starts_to: Some(Utc::now() - chrono::Duration::hours(1)),
            only_available: None,
            limit: Some(0),
        };
        assert!(validate_map_query(&query).is_err());
    }
}
