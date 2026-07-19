use axum::{
    Json,
    extract::{Multipart, Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::Response,
};
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, Postgres, QueryBuilder};
use tracing::warn;
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

use crate::{
    app::AppState,
    modules::{
        media::{cached_image_response, extract_image},
        notifications::{self, NotificationDraft},
        users::active_user_id,
    },
    shared::{errors::AppError, response::ApiResponse},
};

const CATEGORIES: [&str; 11] = [
    "walking",
    "sport",
    "travel",
    "music",
    "games",
    "food",
    "education",
    "animals",
    "help",
    "event",
    "other",
];
const MAX_PARTICIPANT_LIMIT: i32 = 100_000;
const MAX_MAP_ZOOM: f64 = 24.0;

#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ActivityStatus {
    Draft,
    Scheduled,
    #[default]
    Published,
    Full,
    Started,
    Completed,
    Cancelled,
    Expired,
    Hidden,
    Blocked,
}

impl ActivityStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Draft => "draft",
            Self::Scheduled => "scheduled",
            Self::Published => "published",
            Self::Full => "full",
            Self::Started => "started",
            Self::Completed => "completed",
            Self::Cancelled => "cancelled",
            Self::Expired => "expired",
            Self::Hidden => "hidden",
            Self::Blocked => "blocked",
        }
    }
}

#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ApplicationStatus {
    #[default]
    Pending,
    Accepted,
    Rejected,
    Cancelled,
    Expired,
}

impl ApplicationStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Accepted => "accepted",
            Self::Rejected => "rejected",
            Self::Cancelled => "cancelled",
            Self::Expired => "expired",
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ActivityQuestion {
    pub id: Uuid,
    pub kind: String,
    pub prompt: String,
    #[serde(default)]
    pub options: Vec<String>,
    #[serde(default)]
    pub required: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CreateActivityRequest {
    pub title: String,
    #[serde(default)]
    pub description: String,
    pub category: String,
    pub latitude: f64,
    pub longitude: f64,
    pub address: Option<String>,
    pub venue_name: Option<String>,
    #[serde(default = "default_location_visibility")]
    pub location_visibility: String,
    pub starts_at: Option<DateTime<Utc>>,
    #[serde(default = "default_duration")]
    pub duration_minutes: i32,
    pub show_after: Option<DateTime<Utc>>,
    pub hide_after: Option<DateTime<Utc>>,
    pub participant_limit: Option<i32>,
    #[serde(default = "default_join_policy")]
    pub join_policy: String,
    pub age_min: Option<i16>,
    pub age_max: Option<i16>,
    #[serde(default)]
    pub languages: Vec<String>,
    #[serde(default = "default_skill_level")]
    pub skill_level: String,
    #[serde(default = "default_cost_type")]
    pub cost_type: String,
    pub cost_amount_cents: Option<i64>,
    pub cost_note: Option<String>,
    #[serde(default)]
    pub bring_items: Vec<String>,
    #[serde(default)]
    pub rules: Vec<String>,
    #[serde(default)]
    pub additional_questions: Vec<ActivityQuestion>,
    #[serde(default)]
    pub status: ActivityStatus,
}

fn default_duration() -> i32 {
    60
}
fn default_location_visibility() -> String {
    "everyone".into()
}
fn default_join_policy() -> String {
    "request".into()
}
fn default_skill_level() -> String {
    "any".into()
}
fn default_cost_type() -> String {
    "free".into()
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UpdateActivityRequest {
    pub description: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub address: Option<String>,
    pub venue_name: Option<String>,
    pub starts_at: Option<DateTime<Utc>>,
    pub duration_minutes: Option<i32>,
    pub participant_limit: Option<i32>,
    pub recruitment_closed: Option<bool>,
    pub status: Option<ActivityStatus>,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CreateApplicationRequest {
    pub message: Option<String>,
    #[serde(default)]
    pub answers: Vec<ApplicationAnswer>,
}

#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ApplicationAnswer {
    pub question_id: Uuid,
    pub value: String,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UpdateApplicationRequest {
    pub status: ApplicationStatus,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CreateReviewRequest {
    pub subject_id: Uuid,
    pub rating: i16,
    pub comment: Option<String>,
}

#[derive(Debug, Deserialize, IntoParams)]
#[serde(rename_all = "camelCase")]
pub struct MapActivitiesQuery {
    pub south: f64,
    pub west: f64,
    pub north: f64,
    pub east: f64,
    pub zoom: f64,
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
pub struct ActivityLocationResponse {
    pub coordinate: ActivityCoordinateResponse,
    pub address: Option<String>,
    pub venue_name: Option<String>,
    pub visibility: String,
    pub is_exact: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ActivityPhotoResponse {
    pub id: Uuid,
    pub content_path: String,
    pub is_cover: bool,
    pub sort_index: i16,
}

#[derive(Debug, Deserialize, IntoParams)]
#[serde(rename_all = "camelCase")]
pub struct ActivityPhotoUploadQuery {
    pub sort_index: i16,
    #[serde(default)]
    pub is_cover: bool,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ActivityResponse {
    pub id: Uuid,
    pub creator_id: Uuid,
    pub title: String,
    pub description: String,
    pub category: String,
    pub photos: Vec<ActivityPhotoResponse>,
    pub location: ActivityLocationResponse,
    pub starts_at: DateTime<Utc>,
    pub duration_minutes: i32,
    pub show_after: DateTime<Utc>,
    pub hide_after: Option<DateTime<Utc>>,
    pub participant_count: i32,
    pub participant_limit: Option<i32>,
    pub join_policy: String,
    pub age_min: Option<i16>,
    pub age_max: Option<i16>,
    pub languages: Vec<String>,
    pub skill_level: String,
    pub cost_type: String,
    pub cost_amount_cents: Option<i64>,
    pub cost_note: Option<String>,
    pub bring_items: Vec<String>,
    pub rules: Vec<String>,
    pub additional_questions: Vec<ActivityQuestion>,
    pub status: String,
    pub recruitment_closed: bool,
    pub is_organizer: bool,
    pub application_status: Option<String>,
    pub can_access_chat: bool,
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
pub struct ActivityApplicantResponse {
    pub id: Uuid,
    pub display_name: String,
    pub rating: f64,
    pub organized_activities: i64,
    pub avatar_url: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ActivityApplicationResponse {
    pub id: Uuid,
    pub activity_id: Uuid,
    pub applicant: ActivityApplicantResponse,
    pub status: String,
    pub message: Option<String>,
    pub answers: Vec<ApplicationAnswer>,
    pub created_at: DateTime<Utc>,
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
    description: String,
    category: String,
    latitude: f64,
    longitude: f64,
    address: Option<String>,
    venue_name: Option<String>,
    location_visibility: String,
    starts_at: DateTime<Utc>,
    duration_minutes: i32,
    show_after: DateTime<Utc>,
    hide_after: Option<DateTime<Utc>>,
    participant_limit: Option<i32>,
    join_policy: String,
    age_min: Option<i16>,
    age_max: Option<i16>,
    languages: Vec<String>,
    skill_level: String,
    cost_type: String,
    cost_amount_cents: Option<i64>,
    cost_note: Option<String>,
    bring_items: Vec<String>,
    rules: Vec<String>,
    additional_questions: serde_json::Value,
    photos: serde_json::Value,
    status: String,
    recruitment_closed: bool,
    participant_count: i64,
    viewer_application_status: Option<String>,
}

impl ActivityRow {
    fn response(self, viewer_id: Uuid) -> ActivityResponse {
        let is_organizer = self.creator_id == viewer_id;
        let accepted = self.viewer_application_status.as_deref() == Some("accepted");
        let is_exact = can_view_exact_location(
            &self.location_visibility,
            self.starts_at,
            is_organizer,
            accepted,
        );
        let coordinate = visible_coordinate(self.latitude, self.longitude, is_exact);
        ActivityResponse {
            id: self.id,
            creator_id: self.creator_id,
            title: self.title,
            description: self.description,
            category: self.category,
            photos: serde_json::from_value(self.photos).unwrap_or_default(),
            location: ActivityLocationResponse {
                coordinate,
                address: is_exact.then_some(self.address).flatten(),
                venue_name: is_exact.then_some(self.venue_name).flatten(),
                visibility: self.location_visibility,
                is_exact,
            },
            starts_at: self.starts_at,
            duration_minutes: self.duration_minutes,
            show_after: self.show_after,
            hide_after: self.hide_after,
            participant_count: self.participant_count as i32,
            participant_limit: self.participant_limit,
            join_policy: self.join_policy,
            age_min: self.age_min,
            age_max: self.age_max,
            languages: self.languages,
            skill_level: self.skill_level,
            cost_type: self.cost_type,
            cost_amount_cents: self.cost_amount_cents,
            cost_note: self.cost_note,
            bring_items: self.bring_items,
            rules: self.rules,
            additional_questions: serde_json::from_value(self.additional_questions)
                .unwrap_or_default(),
            status: self.status,
            recruitment_closed: self.recruitment_closed,
            is_organizer,
            application_status: self.viewer_application_status,
            can_access_chat: is_organizer || accepted,
        }
    }
}

fn can_view_exact_location(
    visibility: &str,
    starts_at: DateTime<Utc>,
    is_organizer: bool,
    is_accepted: bool,
) -> bool {
    is_organizer
        || visibility == "everyone"
        || (visibility == "accepted_participants" && is_accepted)
        || (visibility == "one_hour_before" && Utc::now() >= starts_at - Duration::hours(1))
}

fn visible_coordinate(latitude: f64, longitude: f64, is_exact: bool) -> ActivityCoordinateResponse {
    if is_exact {
        ActivityCoordinateResponse {
            latitude,
            longitude,
        }
    } else {
        ActivityCoordinateResponse {
            latitude: (latitude * 100.0).round() / 100.0,
            longitude: (longitude * 100.0).round() / 100.0,
        }
    }
}

#[derive(Debug, FromRow)]
struct ApplicationRow {
    id: Uuid,
    activity_id: Uuid,
    applicant_id: Uuid,
    display_name: String,
    rating: f64,
    organized_activities: i64,
    status: String,
    message: Option<String>,
    answers: serde_json::Value,
    created_at: DateTime<Utc>,
}

impl ApplicationRow {
    fn response(self) -> ActivityApplicationResponse {
        ActivityApplicationResponse {
            id: self.id,
            activity_id: self.activity_id,
            applicant: ActivityApplicantResponse {
                id: self.applicant_id,
                display_name: self.display_name,
                rating: self.rating,
                organized_activities: self.organized_activities,
                avatar_url: None,
            },
            status: self.status,
            message: self.message,
            answers: serde_json::from_value(self.answers).unwrap_or_default(),
            created_at: self.created_at,
        }
    }
}

fn validate_coordinates(latitude: f64, longitude: f64) -> bool {
    latitude.is_finite()
        && longitude.is_finite()
        && (-90.0..=90.0).contains(&latitude)
        && (-180.0..=180.0).contains(&longitude)
}

fn cleaned(value: Option<String>, max: usize) -> Option<String> {
    value
        .map(|item| item.trim().chars().take(max).collect())
        .filter(|item: &String| !item.is_empty())
}

fn validation_error(request: &CreateActivityRequest) -> Option<AppError> {
    let mut fields = serde_json::Map::new();
    let title_length = request.title.trim().chars().count();
    if !(2..=70).contains(&title_length) || request.title.chars().any(char::is_control) {
        fields.insert(
            "title".into(),
            "Название должно содержать от 2 до 70 символов".into(),
        );
    }
    if request.description.chars().count() > 3000 {
        fields.insert(
            "description".into(),
            "Описание не должно превышать 3000 символов".into(),
        );
    }
    if !CATEGORIES.contains(&request.category.as_str()) {
        fields.insert("category".into(), "Неизвестная категория активности".into());
    }
    if !validate_coordinates(request.latitude, request.longitude) {
        fields.insert("location".into(), "Укажите корректную геопозицию".into());
    }
    if !(1..=43_200).contains(&request.duration_minutes) {
        fields.insert(
            "durationMinutes".into(),
            "Укажите корректную продолжительность".into(),
        );
    }
    if !["everyone", "accepted_participants", "one_hour_before"]
        .contains(&request.location_visibility.as_str())
    {
        fields.insert(
            "locationVisibility".into(),
            "Неизвестная настройка приватности".into(),
        );
    }
    if !["request", "instant"].contains(&request.join_policy.as_str()) {
        fields.insert("joinPolicy".into(), "Неизвестный способ вступления".into());
    }
    if !["any", "beginner", "intermediate", "experienced"].contains(&request.skill_level.as_str()) {
        fields.insert("skillLevel".into(), "Неизвестный уровень подготовки".into());
    }
    if !["free", "fixed", "self_paid", "estimated"].contains(&request.cost_type.as_str()) {
        fields.insert("costType".into(), "Неизвестный тип стоимости".into());
    }
    if request
        .participant_limit
        .is_some_and(|value| !(2..=MAX_PARTICIPANT_LIMIT).contains(&value))
    {
        fields.insert(
            "participantLimit".into(),
            format!("Количество участников должно быть от 2 до {MAX_PARTICIPANT_LIMIT}").into(),
        );
    }
    if request
        .age_min
        .is_some_and(|value| !(0..=120).contains(&value))
        || request
            .age_max
            .is_some_and(|value| !(0..=120).contains(&value))
        || request
            .age_min
            .zip(request.age_max)
            .is_some_and(|(min, max)| min > max)
    {
        fields.insert(
            "ageRange".into(),
            "Укажите корректный возрастной диапазон".into(),
        );
    }
    if request.additional_questions.len() > 3
        || request
            .additional_questions
            .iter()
            .any(|q| q.prompt.trim().is_empty() || q.prompt.chars().count() > 240)
    {
        fields.insert(
            "additionalQuestions".into(),
            "Можно добавить не более трёх корректных вопросов".into(),
        );
    }
    let show_after = request.show_after.unwrap_or_else(Utc::now);
    if request
        .hide_after
        .is_some_and(|hide_after| hide_after <= show_after)
    {
        fields.insert(
            "hideAfter".into(),
            "Время скрытия должно быть позже времени публикации".into(),
        );
    }
    (!fields.is_empty()).then(|| AppError::validation(serde_json::Value::Object(fields)))
}

fn validate_map_query(query: &MapActivitiesQuery) -> Result<Vec<String>, AppError> {
    let valid = query.south.is_finite()
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
    if !valid {
        return Err(AppError::validation(
            serde_json::json!({"viewport": "Укажите корректные границы карты"}),
        ));
    }
    if query
        .starts_from
        .zip(query.starts_to)
        .is_some_and(|(from, to)| from > to)
    {
        return Err(AppError::validation(
            serde_json::json!({"startsTo": "Конец временного интервала должен быть позже начала"}),
        ));
    }
    if query
        .limit
        .is_some_and(|limit| !(1..=1_000).contains(&limit))
    {
        return Err(AppError::validation(
            serde_json::json!({"limit": "Лимит должен быть от 1 до 1000"}),
        ));
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
        return Err(AppError::validation(
            serde_json::json!({"categories": "Одна или несколько категорий неизвестны"}),
        ));
    }
    Ok(categories)
}

const ACTIVITY_SELECT: &str = "SELECT a.id, a.creator_id, a.title, a.description, a.category, a.latitude, a.longitude, a.address, a.venue_name, a.location_visibility, a.starts_at, a.duration_minutes, a.show_after, a.hide_after, a.participant_limit, a.join_policy, a.age_min, a.age_max, a.languages, a.skill_level, a.cost_type, a.cost_amount_cents, a.cost_note, a.bring_items, a.rules, a.additional_questions, COALESCE((SELECT jsonb_agg(jsonb_build_object('id', photo.id, 'contentPath', 'activities/' || a.id || '/photos/' || photo.id || '/content', 'isCover', photo.is_cover, 'sortIndex', photo.sort_index) ORDER BY photo.sort_index) FROM activity_photos photo WHERE photo.activity_id = a.id), '[]'::jsonb) AS photos, a.status, a.recruitment_closed, 1 + (SELECT COUNT(*) FROM activity_applications accepted WHERE accepted.activity_id = a.id AND accepted.status = 'accepted') AS participant_count, (SELECT viewer_application.status FROM activity_applications viewer_application WHERE viewer_application.activity_id = a.id AND viewer_application.applicant_id = $2) AS viewer_application_status FROM activities a";

async fn fetch_activity(
    state: &AppState,
    activity_id: Uuid,
    viewer_id: Uuid,
) -> Result<ActivityRow, AppError> {
    let query = format!("{ACTIVITY_SELECT} WHERE a.id = $1");
    sqlx::query_as(&query)
        .bind(activity_id)
        .bind(viewer_id)
        .fetch_optional(&state.db)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("ACTIVITY_NOT_FOUND", "Активность не найдена"))
}

#[utoipa::path(post, path = "/api/v1/activities", tag = "activities", security(("bearer_auth" = [])), request_body = CreateActivityRequest, responses((status = 201, body = ActivityResponse), (status = 422, description = "Validation failed")))]
pub async fn create(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<CreateActivityRequest>,
) -> Result<(StatusCode, Json<ApiResponse<ActivityResponse>>), AppError> {
    if let Some(error) = validation_error(&request) {
        return Err(error);
    }
    let viewer_id = active_user_id(&headers, &state).await?;
    let id = Uuid::new_v4();
    let starts_at = request.starts_at.unwrap_or_else(Utc::now);
    let show_after = request.show_after.unwrap_or_else(Utc::now);
    sqlx::query("INSERT INTO activities (id, creator_id, title, description, category, latitude, longitude, address, venue_name, location_visibility, starts_at, duration_minutes, show_after, hide_after, participant_limit, join_policy, age_min, age_max, languages, skill_level, cost_type, cost_amount_cents, cost_note, bring_items, rules, additional_questions, status) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27)")
        .bind(id).bind(viewer_id).bind(request.title.trim()).bind(request.description.trim())
        .bind(request.category).bind(request.latitude).bind(request.longitude)
        .bind(cleaned(request.address, 500)).bind(cleaned(request.venue_name, 120))
        .bind(request.location_visibility).bind(starts_at).bind(request.duration_minutes)
        .bind(show_after).bind(request.hide_after).bind(request.participant_limit)
        .bind(request.join_policy).bind(request.age_min).bind(request.age_max)
        .bind(request.languages).bind(request.skill_level).bind(request.cost_type)
        .bind(request.cost_amount_cents).bind(cleaned(request.cost_note, 240))
        .bind(request.bring_items).bind(request.rules)
        .bind(serde_json::to_value(request.additional_questions).map_err(AppError::internal)?)
        .bind(request.status.as_str()).execute(&state.db).await.map_err(AppError::internal)?;
    let response = fetch_activity(&state, id, viewer_id)
        .await?
        .response(viewer_id);
    Ok((StatusCode::CREATED, Json(ApiResponse::new(response))))
}

#[utoipa::path(get, path = "/api/v1/activities/{activity_id}", tag = "activities", security(("bearer_auth" = [])), params(("activity_id" = Uuid, Path)), responses((status = 200, body = ActivityResponse), (status = 404, description = "Activity not found")))]
pub async fn detail(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(activity_id): Path<Uuid>,
) -> Result<Json<ApiResponse<ActivityResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    Ok(Json(ApiResponse::new(
        fetch_activity(&state, activity_id, viewer_id)
            .await?
            .response(viewer_id),
    )))
}

#[utoipa::path(get, path = "/api/v1/activities/mine", tag = "activities", security(("bearer_auth" = [])), responses((status = 200, body = Vec<ActivityResponse>)))]
pub async fn mine(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<Vec<ActivityResponse>>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let query = format!("{ACTIVITY_SELECT} WHERE a.creator_id = $1 ORDER BY a.created_at DESC");
    let rows: Vec<ActivityRow> = sqlx::query_as(&query)
        .bind(viewer_id)
        .bind(viewer_id)
        .fetch_all(&state.db)
        .await
        .map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(
        rows.into_iter()
            .map(|row| row.response(viewer_id))
            .collect(),
    )))
}

#[utoipa::path(patch, path = "/api/v1/activities/{activity_id}", tag = "activities", security(("bearer_auth" = [])), request_body = UpdateActivityRequest, responses((status = 200, body = ActivityResponse), (status = 403, description = "Organizer only")))]
pub async fn update(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(activity_id): Path<Uuid>,
    Json(request): Json<UpdateActivityRequest>,
) -> Result<Json<ApiResponse<ActivityResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let current = fetch_activity(&state, activity_id, viewer_id).await?;
    if current.creator_id != viewer_id {
        return Err(AppError::forbidden(
            "ACTIVITY_ORGANIZER_REQUIRED",
            "Действие доступно только организатору",
        ));
    }
    if request
        .latitude
        .zip(request.longitude)
        .is_some_and(|(lat, lon)| !validate_coordinates(lat, lon))
    {
        return Err(AppError::validation(
            serde_json::json!({"location": "Укажите корректную геопозицию"}),
        ));
    }
    let important_details_changed =
        request.latitude.is_some() || request.longitude.is_some() || request.starts_at.is_some();
    let activity_cancelled = request.status == Some(ActivityStatus::Cancelled);
    sqlx::query("UPDATE activities SET description = COALESCE($2, description), latitude = COALESCE($3, latitude), longitude = COALESCE($4, longitude), address = COALESCE($5, address), venue_name = COALESCE($6, venue_name), starts_at = COALESCE($7, starts_at), duration_minutes = COALESCE($8, duration_minutes), participant_limit = COALESCE($9, participant_limit), recruitment_closed = COALESCE($10, recruitment_closed), status = COALESCE($11, status), updated_at = NOW() WHERE id = $1")
        .bind(activity_id).bind(request.description.map(|value| value.trim().chars().take(3000).collect::<String>()))
        .bind(request.latitude).bind(request.longitude).bind(cleaned(request.address, 500))
        .bind(cleaned(request.venue_name, 120)).bind(request.starts_at).bind(request.duration_minutes)
        .bind(request.participant_limit).bind(request.recruitment_closed)
        .bind(request.status.map(ActivityStatus::as_str)).execute(&state.db).await.map_err(AppError::internal)?;
    if activity_cancelled {
        enqueue_participant_notifications(
            &state,
            activity_id,
            ParticipantNotification {
                organizer_id: viewer_id,
                activity_title: &current.title,
                kind: "activity_cancelled",
                title: "Активность отменена",
                body: format!("Организатор отменил «{}»", current.title),
                deduplicate: true,
            },
        )
        .await?;
    } else if important_details_changed {
        enqueue_participant_notifications(
            &state,
            activity_id,
            ParticipantNotification {
                organizer_id: viewer_id,
                activity_title: &current.title,
                kind: "activity_updated",
                title: "Место или время изменились",
                body: format!("Проверьте новые детали активности «{}»", current.title),
                deduplicate: false,
            },
        )
        .await?;
    }
    Ok(Json(ApiResponse::new(
        fetch_activity(&state, activity_id, viewer_id)
            .await?
            .response(viewer_id),
    )))
}

#[utoipa::path(post, path = "/api/v1/activities/{activity_id}/applications", tag = "activities", security(("bearer_auth" = [])), request_body = CreateApplicationRequest, responses((status = 201, body = ActivityApplicationResponse), (status = 409, description = "Activity unavailable")))]
pub async fn apply(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(activity_id): Path<Uuid>,
    Json(request): Json<CreateApplicationRequest>,
) -> Result<(StatusCode, Json<ApiResponse<ActivityApplicationResponse>>), AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let activity = fetch_activity(&state, activity_id, viewer_id).await?;
    if activity.creator_id == viewer_id {
        return Err(AppError::conflict(
            "ORGANIZER_ALREADY_PARTICIPATES",
            "Организатор уже является участником",
        ));
    }
    if activity.recruitment_closed
        || !["published", "scheduled"].contains(&activity.status.as_str())
    {
        return Err(AppError::conflict(
            "ACTIVITY_CLOSED",
            "Набор в активность закрыт",
        ));
    }
    if activity
        .participant_limit
        .is_some_and(|limit| activity.participant_count >= i64::from(limit))
    {
        return Err(AppError::conflict(
            "ACTIVITY_FULL",
            "В активности больше нет свободных мест",
        ));
    }
    let status = if activity.join_policy == "instant" {
        "accepted"
    } else {
        "pending"
    };
    let application_id = Uuid::new_v4();
    let row: ApplicationRow = sqlx::query_as("WITH inserted AS (INSERT INTO activity_applications (id, activity_id, applicant_id, status, message, answers) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (activity_id, applicant_id) DO UPDATE SET status = EXCLUDED.status, message = EXCLUDED.message, answers = EXCLUDED.answers, updated_at = NOW() RETURNING *) SELECT inserted.id, inserted.activity_id, inserted.applicant_id, users.display_name, users.rating, (SELECT COUNT(*) FROM activities owned WHERE owned.creator_id = users.id AND owned.status IN ('completed','published','started')) AS organized_activities, inserted.status, inserted.message, inserted.answers, inserted.created_at FROM inserted JOIN users ON users.id = inserted.applicant_id")
        .bind(application_id).bind(activity_id).bind(viewer_id).bind(status)
        .bind(cleaned(request.message, 1000))
        .bind(serde_json::to_value(request.answers).map_err(AppError::internal)?)
        .fetch_one(&state.db).await.map_err(AppError::internal)?;
    let accepted_immediately = status == "accepted";
    notifications::emit(
        &state,
        NotificationDraft {
            recipient_id: activity.creator_id,
            actor_id: Some(viewer_id),
            category: "activities",
            kind: "activity_application",
            title: if accepted_immediately {
                "Новый участник".into()
            } else {
                "Новая заявка".into()
            },
            body: if accepted_immediately {
                format!("{} присоединился к «{}»", row.display_name, activity.title)
            } else {
                format!(
                    "{} хочет присоединиться к «{}»",
                    row.display_name, activity.title
                )
            },
            entity_type: Some("activity"),
            entity_id: Some(activity_id),
            action_path: Some(format!("gonow://activities/{activity_id}")),
            payload: serde_json::json!({"applicationId": row.id, "status": status}),
            dedupe_key: Some(format!("activity-application:{}", row.id)),
        },
    )
    .await?;
    Ok((StatusCode::CREATED, Json(ApiResponse::new(row.response()))))
}

#[utoipa::path(get, path = "/api/v1/activities/{activity_id}/applications", tag = "activities", security(("bearer_auth" = [])), responses((status = 200, body = Vec<ActivityApplicationResponse>), (status = 403, description = "Organizer only")))]
pub async fn applications(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(activity_id): Path<Uuid>,
) -> Result<Json<ApiResponse<Vec<ActivityApplicationResponse>>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let activity = fetch_activity(&state, activity_id, viewer_id).await?;
    if activity.creator_id != viewer_id {
        return Err(AppError::forbidden(
            "ACTIVITY_ORGANIZER_REQUIRED",
            "Заявки доступны только организатору",
        ));
    }
    let rows: Vec<ApplicationRow> = sqlx::query_as("SELECT application.id, application.activity_id, application.applicant_id, users.display_name, users.rating, (SELECT COUNT(*) FROM activities owned WHERE owned.creator_id = users.id AND owned.status IN ('completed','published','started')) AS organized_activities, application.status, application.message, application.answers, application.created_at FROM activity_applications application JOIN users ON users.id = application.applicant_id WHERE application.activity_id = $1 ORDER BY application.created_at DESC")
        .bind(activity_id).fetch_all(&state.db).await.map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(
        rows.into_iter().map(ApplicationRow::response).collect(),
    )))
}

#[utoipa::path(patch, path = "/api/v1/activities/{activity_id}/applications/{application_id}", tag = "activities", security(("bearer_auth" = [])), request_body = UpdateApplicationRequest, responses((status = 200, body = ActivityApplicationResponse), (status = 403, description = "Organizer only")))]
pub async fn update_application(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path((activity_id, application_id)): Path<(Uuid, Uuid)>,
    Json(request): Json<UpdateApplicationRequest>,
) -> Result<Json<ApiResponse<ActivityApplicationResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let activity = fetch_activity(&state, activity_id, viewer_id).await?;
    if activity.creator_id != viewer_id {
        return Err(AppError::forbidden(
            "ACTIVITY_ORGANIZER_REQUIRED",
            "Действие доступно только организатору",
        ));
    }
    if request.status == ApplicationStatus::Accepted
        && activity
            .participant_limit
            .is_some_and(|limit| activity.participant_count >= i64::from(limit))
    {
        return Err(AppError::conflict(
            "ACTIVITY_FULL",
            "В активности больше нет свободных мест",
        ));
    }
    let row: ApplicationRow = sqlx::query_as("WITH changed AS (UPDATE activity_applications SET status = $3, updated_at = NOW() WHERE id = $1 AND activity_id = $2 RETURNING *) SELECT changed.id, changed.activity_id, changed.applicant_id, users.display_name, users.rating, (SELECT COUNT(*) FROM activities owned WHERE owned.creator_id = users.id AND owned.status IN ('completed','published','started')) AS organized_activities, changed.status, changed.message, changed.answers, changed.created_at FROM changed JOIN users ON users.id = changed.applicant_id")
        .bind(application_id).bind(activity_id).bind(request.status.as_str())
        .fetch_optional(&state.db).await.map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("APPLICATION_NOT_FOUND", "Заявка не найдена"))?;
    let accepted = request.status == ApplicationStatus::Accepted;
    notifications::emit(
        &state,
        NotificationDraft {
            recipient_id: row.applicant_id,
            actor_id: Some(viewer_id),
            category: "activities",
            kind: "application_status",
            title: if accepted {
                "Заявка принята".into()
            } else {
                "Статус заявки изменён".into()
            },
            body: if accepted {
                format!("Вы участвуете в «{}»", activity.title)
            } else {
                format!("Статус вашей заявки на «{}»: {}", activity.title, request.status.as_str())
            },
            entity_type: Some("activity"),
            entity_id: Some(activity_id),
            action_path: Some(format!("gonow://activities/{activity_id}")),
            payload: serde_json::json!({"applicationId": row.id, "status": request.status.as_str()}),
            dedupe_key: Some(format!(
                "application-status:{}:{}",
                row.id,
                request.status.as_str()
            )),
        },
    )
    .await?;
    Ok(Json(ApiResponse::new(row.response())))
}

#[utoipa::path(post, path = "/api/v1/activities/{activity_id}/duplicate", tag = "activities", security(("bearer_auth" = [])), responses((status = 201, body = ActivityResponse)))]
pub async fn duplicate(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(activity_id): Path<Uuid>,
) -> Result<(StatusCode, Json<ApiResponse<ActivityResponse>>), AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let source = fetch_activity(&state, activity_id, viewer_id).await?;
    if source.creator_id != viewer_id {
        return Err(AppError::forbidden(
            "ACTIVITY_ORGANIZER_REQUIRED",
            "Действие доступно только организатору",
        ));
    }
    let id = Uuid::new_v4();
    sqlx::query("INSERT INTO activities (id, creator_id, title, description, category, latitude, longitude, address, venue_name, location_visibility, starts_at, duration_minutes, show_after, participant_limit, join_policy, age_min, age_max, languages, skill_level, cost_type, cost_amount_cents, cost_note, bring_items, rules, additional_questions, status) SELECT $1, creator_id, title, description, category, latitude, longitude, address, venue_name, location_visibility, NOW(), duration_minutes, NOW(), participant_limit, join_policy, age_min, age_max, languages, skill_level, cost_type, cost_amount_cents, cost_note, bring_items, rules, additional_questions, 'draft' FROM activities WHERE id = $2")
        .bind(id).bind(activity_id).execute(&state.db).await.map_err(AppError::internal)?;
    Ok((
        StatusCode::CREATED,
        Json(ApiResponse::new(
            fetch_activity(&state, id, viewer_id)
                .await?
                .response(viewer_id),
        )),
    ))
}

#[utoipa::path(post, path = "/api/v1/activities/{activity_id}/photos", tag = "activities", security(("bearer_auth" = [])), params(("activity_id" = Uuid, Path), ActivityPhotoUploadQuery), request_body(content = String, content_type = "multipart/form-data"), responses((status = 201, body = ActivityPhotoResponse), (status = 403, description = "Organizer only"), (status = 503, description = "Object storage unavailable")))]
pub async fn upload_photo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(activity_id): Path<Uuid>,
    Query(query): Query<ActivityPhotoUploadQuery>,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<ApiResponse<ActivityPhotoResponse>>), AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let activity = fetch_activity(&state, activity_id, viewer_id).await?;
    if activity.creator_id != viewer_id {
        return Err(AppError::forbidden(
            "ACTIVITY_ORGANIZER_REQUIRED",
            "Фотографии может менять только организатор",
        ));
    }
    if !(0..=5).contains(&query.sort_index) {
        return Err(AppError::validation(serde_json::json!({
            "sortIndex": "Позиция фотографии должна быть от 0 до 5"
        })));
    }
    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM activity_photos WHERE activity_id = $1")
            .bind(activity_id)
            .fetch_one(&state.db)
            .await
            .map_err(AppError::internal)?;
    if count >= 6 {
        return Err(AppError::conflict(
            "ACTIVITY_PHOTO_LIMIT_REACHED",
            "Можно добавить не более шести фотографий",
        ));
    }
    let storage = state.object_storage.clone().ok_or_else(|| AppError {
        status: StatusCode::SERVICE_UNAVAILABLE,
        code: "OBJECT_STORAGE_UNAVAILABLE",
        message: "Хранилище фотографий пока не настроено".into(),
        fields: None,
    })?;
    let image = extract_image(&mut multipart).await?;
    let photo_id = Uuid::new_v4();
    let object_key = storage.activity_object_key(activity_id, photo_id, image.extension);
    let bytes = i32::try_from(image.data.len()).map_err(AppError::internal)?;
    storage
        .put_image(&object_key, image.content_type, image.data)
        .await
        .map_err(|error| {
            warn!(error = %error, activity_id = %activity_id, "activity image upload failed");
            AppError::service_unavailable()
        })?;

    let is_cover = query.is_cover || count == 0;
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    if is_cover {
        sqlx::query("UPDATE activity_photos SET is_cover = FALSE WHERE activity_id = $1")
            .bind(activity_id)
            .execute(&mut *tx)
            .await
            .map_err(AppError::internal)?;
    }
    let inserted = sqlx::query("INSERT INTO activity_photos (id, activity_id, object_key, content_type, bytes, sort_index, is_cover) VALUES ($1,$2,$3,$4,$5,$6,$7)")
        .bind(photo_id).bind(activity_id).bind(&object_key).bind(image.content_type)
        .bind(bytes).bind(query.sort_index).bind(is_cover)
        .execute(&mut *tx).await;
    if let Err(error) = inserted {
        tx.rollback().await.ok();
        if let Err(cleanup_error) = storage.delete(&object_key).await {
            warn!(error = %cleanup_error, object_key = %object_key, "failed to clean up activity image");
        }
        return Err(AppError::internal(error));
    }
    tx.commit().await.map_err(AppError::internal)?;
    Ok((
        StatusCode::CREATED,
        Json(ApiResponse::new(ActivityPhotoResponse {
            id: photo_id,
            content_path: format!("activities/{activity_id}/photos/{photo_id}/content"),
            is_cover,
            sort_index: query.sort_index,
        })),
    ))
}

#[utoipa::path(get, path = "/api/v1/activities/{activity_id}/photos/{photo_id}/content", tag = "activities", security(("bearer_auth" = [])), params(("activity_id" = Uuid, Path), ("photo_id" = Uuid, Path)), responses((status = 200, description = "Activity image bytes"), (status = 404, description = "Photo not found")))]
pub async fn download_photo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path((activity_id, photo_id)): Path<(Uuid, Uuid)>,
) -> Result<Response, AppError> {
    let _viewer_id = active_user_id(&headers, &state).await?;
    let photo = sqlx::query_as::<_, (String, String)>(
        "SELECT object_key, content_type FROM activity_photos WHERE id = $1 AND activity_id = $2",
    )
    .bind(photo_id)
    .bind(activity_id)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?
    .ok_or_else(|| AppError::not_found("ACTIVITY_PHOTO_NOT_FOUND", "Фотография не найдена"))?;
    cached_image_response(&state, &headers, &photo.0, &photo.1, photo_id).await
}

#[utoipa::path(post, path = "/api/v1/activities/{activity_id}/reviews", tag = "activities", security(("bearer_auth" = [])), request_body = CreateReviewRequest, responses((status = 201, description = "Review stored")))]
pub async fn review(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(activity_id): Path<Uuid>,
    Json(request): Json<CreateReviewRequest>,
) -> Result<StatusCode, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    if !(1..=5).contains(&request.rating) {
        return Err(AppError::validation(
            serde_json::json!({"rating": "Оценка должна быть от 1 до 5"}),
        ));
    }
    let activity = fetch_activity(&state, activity_id, viewer_id).await?;
    let is_participant = activity.creator_id == viewer_id
        || activity.viewer_application_status.as_deref() == Some("accepted");
    if activity.status != "completed" || !is_participant {
        return Err(AppError::forbidden(
            "REVIEW_NOT_ALLOWED",
            "Отзыв доступен только участникам завершённой активности",
        ));
    }
    sqlx::query("INSERT INTO activity_reviews (id, activity_id, author_id, subject_id, rating, comment) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (activity_id, author_id, subject_id) DO UPDATE SET rating = EXCLUDED.rating, comment = EXCLUDED.comment")
        .bind(Uuid::new_v4()).bind(activity_id).bind(viewer_id).bind(request.subject_id)
        .bind(request.rating).bind(cleaned(request.comment, 2000)).execute(&state.db).await.map_err(AppError::internal)?;
    Ok(StatusCode::CREATED)
}

struct ParticipantNotification<'a> {
    organizer_id: Uuid,
    activity_title: &'a str,
    kind: &'static str,
    title: &'a str,
    body: String,
    deduplicate: bool,
}

async fn enqueue_participant_notifications(
    state: &AppState,
    activity_id: Uuid,
    notification: ParticipantNotification<'_>,
) -> Result<(), AppError> {
    let recipients = sqlx::query_scalar::<_, Uuid>(
        "SELECT applicant_id FROM activity_applications WHERE activity_id = $1 AND status = 'accepted'",
    )
    .bind(activity_id)
    .fetch_all(&state.db)
    .await
    .map_err(AppError::internal)?;
    for recipient_id in recipients {
        notifications::emit(
            state,
            NotificationDraft {
                recipient_id,
                actor_id: Some(notification.organizer_id),
                category: "activities",
                kind: notification.kind,
                title: notification.title.into(),
                body: notification.body.clone(),
                entity_type: Some("activity"),
                entity_id: Some(activity_id),
                action_path: Some(format!("gonow://activities/{activity_id}")),
                payload: serde_json::json!({"activityTitle": notification.activity_title}),
                dedupe_key: notification
                    .deduplicate
                    .then(|| format!("{}:{activity_id}:{recipient_id}", notification.kind)),
            },
        )
        .await?;
    }
    Ok(())
}

#[utoipa::path(get, path = "/api/v1/activities/map", tag = "activities", security(("bearer_auth" = [])), params(MapActivitiesQuery), responses((status = 200, body = MapActivitiesEnvelope)))]
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
        "SELECT a.id, a.creator_id, a.title, a.category, a.latitude, a.longitude, a.location_visibility, a.starts_at, a.participant_limit, 1 + COALESCE(stats.participant_count, 0) AS participant_count, (a.creator_id = ",
    );
    builder
        .push_bind(viewer_id)
        .push(" OR COALESCE(stats.is_joined, FALSE)) AS is_joined FROM activities a LEFT JOIN LATERAL (SELECT COUNT(*) FILTER (WHERE application.status = 'accepted') AS participant_count, BOOL_OR(application.applicant_id = ")
        .push_bind(viewer_id)
        .push(" AND application.status = 'accepted') AS is_joined FROM activity_applications application WHERE application.activity_id = a.id) stats ON TRUE WHERE a.status IN ('published','full','scheduled') AND a.show_after <= NOW() AND (a.hide_after IS NULL OR a.hide_after > NOW()) AND a.latitude BETWEEN ")
        .push_bind(query.south)
        .push(" AND ")
        .push_bind(query.north);
    if query.west <= query.east {
        builder
            .push(" AND a.longitude BETWEEN ")
            .push_bind(query.west)
            .push(" AND ")
            .push_bind(query.east);
    } else {
        builder
            .push(" AND (a.longitude >= ")
            .push_bind(query.west)
            .push(" OR a.longitude <= ")
            .push_bind(query.east)
            .push(")");
    }
    if let Some(from) = query.starts_from {
        builder.push(" AND a.starts_at >= ").push_bind(from);
    }
    if let Some(to) = query.starts_to {
        builder.push(" AND a.starts_at <= ").push_bind(to);
    }
    if !categories.is_empty() {
        builder
            .push(" AND a.category = ANY(")
            .push_bind(categories)
            .push(")");
    }
    if query.only_available.unwrap_or(false) {
        builder.push(" AND NOT a.recruitment_closed AND (a.participant_limit IS NULL OR a.participant_limit > 1 + COALESCE(stats.participant_count, 0))");
    }
    builder
        .push(" ORDER BY a.starts_at ASC, a.id ASC LIMIT ")
        .push_bind(fetch_limit);

    #[derive(FromRow)]
    struct MapRow {
        id: Uuid,
        creator_id: Uuid,
        title: String,
        category: String,
        latitude: f64,
        longitude: f64,
        location_visibility: String,
        starts_at: DateTime<Utc>,
        participant_limit: Option<i32>,
        participant_count: i64,
        is_joined: bool,
    }
    let mut rows: Vec<MapRow> = builder
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
        .map(|row| {
            let is_joined = row.is_joined || row.creator_id == viewer_id;
            let is_exact = can_view_exact_location(
                &row.location_visibility,
                row.starts_at,
                row.creator_id == viewer_id,
                row.is_joined,
            );
            MapActivityResponse {
                id: row.id,
                title: row.title,
                category: row.category,
                coordinate: visible_coordinate(row.latitude, row.longitude, is_exact),
                starts_at: row.starts_at,
                participant_count: row.participant_count as i32,
                participant_limit: row.participant_limit,
                distance_meters: None,
                image_url: None,
                is_joined,
            }
        })
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

    fn valid_request() -> CreateActivityRequest {
        CreateActivityRequest {
            title: "Прогулка".into(),
            description: String::new(),
            category: "walking".into(),
            latitude: 55.7558,
            longitude: 37.6173,
            address: None,
            venue_name: None,
            location_visibility: default_location_visibility(),
            starts_at: None,
            duration_minutes: default_duration(),
            show_after: None,
            hide_after: None,
            participant_limit: None,
            join_policy: default_join_policy(),
            age_min: None,
            age_max: None,
            languages: vec![],
            skill_level: default_skill_level(),
            cost_type: default_cost_type(),
            cost_amount_cents: None,
            cost_note: None,
            bring_items: vec![],
            rules: vec![],
            additional_questions: vec![],
            status: ActivityStatus::Published,
        }
    }

    #[test]
    fn validates_coordinates() {
        assert!(validate_coordinates(55.7558, 37.6173));
        assert!(!validate_coordinates(91.0, 37.6173));
        assert!(!validate_coordinates(55.7558, f64::NAN));
    }

    #[test]
    fn rejects_unknown_category_and_long_title() {
        let mut request = valid_request();
        request.category = "unknown".into();
        request.title = "x".repeat(71);
        assert!(validation_error(&request).is_some());
    }

    #[test]
    fn accepts_full_lifecycle_request() {
        let mut request = valid_request();
        request.category = "event".into();
        request.additional_questions.push(ActivityQuestion {
            id: Uuid::new_v4(),
            kind: "yes_no".into(),
            prompt: "Придёте вовремя?".into(),
            options: vec![],
            required: true,
        });
        assert!(validation_error(&request).is_none());
    }

    #[test]
    fn protects_private_location_on_detail_and_map() {
        let starts_later = Utc::now() + Duration::hours(2);
        assert!(!can_view_exact_location(
            "accepted_participants",
            starts_later,
            false,
            false
        ));
        assert!(can_view_exact_location(
            "accepted_participants",
            starts_later,
            false,
            true
        ));
        assert!(!can_view_exact_location(
            "one_hour_before",
            starts_later,
            false,
            false
        ));

        let approximate = visible_coordinate(55.7558, 37.6173, false);
        assert_eq!(approximate.latitude, 55.76);
        assert_eq!(approximate.longitude, 37.62);
        let exact = visible_coordinate(55.7558, 37.6173, true);
        assert_eq!(exact.latitude, 55.7558);
        assert_eq!(exact.longitude, 37.6173);
    }
}
