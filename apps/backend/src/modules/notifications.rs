use std::time::Duration as StdDuration;

use axum::{
    Json,
    extract::{
        Path, Query, State, WebSocketUpgrade,
        ws::{Message, WebSocket},
    },
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
};
use chrono::{DateTime, Utc};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::FromRow;
use tracing::{info, warn};
use uuid::Uuid;

use crate::{
    app::AppState,
    infrastructure::apns::{ApnsError, ApnsPush},
    shared::{errors::AppError, response::ApiResponse},
};

use super::users::active_user_id;

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NotificationRealtimeEvent {
    pub event: String,
    pub recipient_id: Uuid,
    pub notification_id: Option<Uuid>,
    pub unread_count: i64,
}

#[derive(Debug, Clone)]
pub struct NotificationDraft {
    pub recipient_id: Uuid,
    pub actor_id: Option<Uuid>,
    pub category: &'static str,
    pub kind: &'static str,
    pub title: String,
    pub body: String,
    pub entity_type: Option<&'static str>,
    pub entity_id: Option<Uuid>,
    pub action_path: Option<String>,
    pub payload: Value,
    pub dedupe_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, FromRow)]
#[serde(rename_all = "camelCase")]
pub struct NotificationResponse {
    pub id: Uuid,
    pub actor_id: Option<Uuid>,
    pub actor_name: Option<String>,
    pub actor_avatar_path: Option<String>,
    pub category: String,
    pub kind: String,
    pub title: String,
    pub body: String,
    pub entity_type: Option<String>,
    pub entity_id: Option<Uuid>,
    pub action_path: Option<String>,
    pub payload: Value,
    pub is_read: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NotificationListData {
    pub items: Vec<NotificationResponse>,
    pub unread_count: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UnreadCountData {
    pub unread_count: i64,
}

#[derive(Debug, Clone, Serialize, FromRow)]
#[serde(rename_all = "camelCase")]
pub struct NotificationSettingsResponse {
    pub push_enabled: bool,
    pub friend_requests: bool,
    pub messages: bool,
    pub invitations: bool,
    pub activities: bool,
    pub sound_enabled: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateNotificationSettingsRequest {
    pub push_enabled: bool,
    pub friend_requests: bool,
    pub messages: bool,
    pub invitations: bool,
    pub activities: bool,
    pub sound_enabled: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterPushDeviceRequest {
    pub device_id: String,
    pub token: String,
    pub environment: String,
    pub app_bundle: String,
    pub locale: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NotificationListQuery {
    pub category: Option<String>,
    pub unread_only: Option<bool>,
    pub limit: Option<i64>,
}

const NOTIFICATION_SELECT: &str = r#"
SELECT notification.id, notification.actor_id, actor.display_name AS actor_name,
       CASE WHEN avatar.id IS NULL THEN NULL ELSE 'users/photos/' || avatar.id || '/content' END AS actor_avatar_path,
       notification.category, notification.kind, notification.title, notification.body,
       notification.entity_type, notification.entity_id, notification.action_path,
       notification.payload, (notification.read_at IS NOT NULL) AS is_read,
       notification.created_at
FROM notifications notification
LEFT JOIN users actor ON actor.id = notification.actor_id
LEFT JOIN LATERAL (
    SELECT id FROM user_photos
    WHERE user_id = actor.id AND is_current_avatar = TRUE LIMIT 1
) avatar ON TRUE
"#;

pub async fn list(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<NotificationListQuery>,
) -> Result<Json<ApiResponse<NotificationListData>>, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    let limit = query.limit.unwrap_or(100).clamp(1, 200);
    let category = query.category.filter(|value| {
        matches!(
            value.as_str(),
            "social" | "messages" | "activities" | "system"
        )
    });
    let sql = format!(
        "{NOTIFICATION_SELECT} WHERE notification.recipient_id = $1 AND ($2::text IS NULL OR notification.category = $2) AND (NOT $3 OR notification.read_at IS NULL) ORDER BY notification.created_at DESC, notification.id DESC LIMIT $4"
    );
    let items = sqlx::query_as::<_, NotificationResponse>(&sql)
        .bind(user_id)
        .bind(category)
        .bind(query.unread_only.unwrap_or(false))
        .bind(limit)
        .fetch_all(&state.db)
        .await
        .map_err(AppError::internal)?;
    let unread_count = unread_count(&state, user_id).await?;
    Ok(Json(ApiResponse::new(NotificationListData {
        items,
        unread_count,
    })))
}

pub async fn unread(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<UnreadCountData>>, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    Ok(Json(ApiResponse::new(UnreadCountData {
        unread_count: unread_count(&state, user_id).await?,
    })))
}

pub async fn mark_read(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(notification_id): Path<Uuid>,
) -> Result<Json<ApiResponse<NotificationResponse>>, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    let changed = sqlx::query(
        "UPDATE notifications SET read_at = COALESCE(read_at, NOW()) WHERE id = $1 AND recipient_id = $2",
    )
    .bind(notification_id)
    .bind(user_id)
    .execute(&state.db)
    .await
    .map_err(AppError::internal)?;
    if changed.rows_affected() == 0 {
        return Err(AppError::not_found(
            "NOTIFICATION_NOT_FOUND",
            "Уведомление не найдено",
        ));
    }
    let notification = notification_by_id(&state, user_id, notification_id).await?;
    broadcast_count(&state, user_id, Some(notification_id), "read").await?;
    Ok(Json(ApiResponse::new(notification)))
}

pub async fn mark_all_read(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<UnreadCountData>>, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    sqlx::query(
        "UPDATE notifications SET read_at = NOW() WHERE recipient_id = $1 AND read_at IS NULL",
    )
    .bind(user_id)
    .execute(&state.db)
    .await
    .map_err(AppError::internal)?;
    broadcast_count(&state, user_id, None, "readAll").await?;
    Ok(Json(ApiResponse::new(UnreadCountData { unread_count: 0 })))
}

pub async fn delete(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(notification_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    sqlx::query("DELETE FROM notifications WHERE id = $1 AND recipient_id = $2")
        .bind(notification_id)
        .bind(user_id)
        .execute(&state.db)
        .await
        .map_err(AppError::internal)?;
    broadcast_count(&state, user_id, Some(notification_id), "deleted").await?;
    Ok(StatusCode::NO_CONTENT)
}

pub async fn settings(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<NotificationSettingsResponse>>, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    Ok(Json(ApiResponse::new(
        notification_settings(&state, user_id).await?,
    )))
}

pub async fn update_settings(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<UpdateNotificationSettingsRequest>,
) -> Result<Json<ApiResponse<NotificationSettingsResponse>>, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    let settings = sqlx::query_as::<_, NotificationSettingsResponse>(
        r#"INSERT INTO notification_preferences
           (user_id, push_enabled, friend_requests, messages, invitations, activities, sound_enabled)
           VALUES ($1,$2,$3,$4,$5,$6,$7)
           ON CONFLICT (user_id) DO UPDATE SET
             push_enabled = EXCLUDED.push_enabled,
             friend_requests = EXCLUDED.friend_requests,
             messages = EXCLUDED.messages,
             invitations = EXCLUDED.invitations,
             activities = EXCLUDED.activities,
             sound_enabled = EXCLUDED.sound_enabled,
             updated_at = NOW()
           RETURNING push_enabled, friend_requests, messages, invitations, activities, sound_enabled"#,
    )
    .bind(user_id)
    .bind(request.push_enabled)
    .bind(request.friend_requests)
    .bind(request.messages)
    .bind(request.invitations)
    .bind(request.activities)
    .bind(request.sound_enabled)
    .fetch_one(&state.db)
    .await
    .map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(settings)))
}

pub async fn register_device(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<RegisterPushDeviceRequest>,
) -> Result<StatusCode, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    let device_id = request.device_id.trim();
    let token = request.token.trim().to_ascii_lowercase();
    let app_bundle = request.app_bundle.trim();
    if device_id.is_empty()
        || device_id.chars().count() > 128
        || !(32..=256).contains(&token.len())
        || !token.chars().all(|value| value.is_ascii_hexdigit())
        || !matches!(request.environment.as_str(), "sandbox" | "production")
        || app_bundle.is_empty()
        || app_bundle.chars().count() > 180
    {
        return Err(AppError::validation(serde_json::json!({
            "device": "Некорректные данные push-устройства"
        })));
    }
    let locale = request
        .locale
        .as_deref()
        .unwrap_or("ru")
        .trim()
        .chars()
        .take(16)
        .collect::<String>();
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    sqlx::query("DELETE FROM push_devices WHERE user_id = $1 AND device_id = $2 AND environment = $3 AND app_bundle = $4 AND token <> $5")
        .bind(user_id)
        .bind(device_id)
        .bind(&request.environment)
        .bind(app_bundle)
        .bind(&token)
        .execute(&mut *tx)
        .await
        .map_err(AppError::internal)?;
    sqlx::query(
        r#"INSERT INTO push_devices
           (id, user_id, device_id, token, environment, app_bundle, locale)
           VALUES ($1,$2,$3,$4,$5,$6,$7)
           ON CONFLICT (token) DO UPDATE SET
             user_id = EXCLUDED.user_id, device_id = EXCLUDED.device_id,
             environment = EXCLUDED.environment, app_bundle = EXCLUDED.app_bundle,
             locale = EXCLUDED.locale, enabled = TRUE, last_seen_at = NOW()"#,
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(device_id)
    .bind(token)
    .bind(request.environment)
    .bind(app_bundle)
    .bind(locale)
    .execute(&mut *tx)
    .await
    .map_err(AppError::internal)?;
    tx.commit().await.map_err(AppError::internal)?;
    Ok(StatusCode::NO_CONTENT)
}

pub async fn unregister_device(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(device_id): Path<String>,
) -> Result<StatusCode, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    sqlx::query("DELETE FROM push_devices WHERE user_id = $1 AND device_id = $2")
        .bind(user_id)
        .bind(device_id)
        .execute(&state.db)
        .await
        .map_err(AppError::internal)?;
    Ok(StatusCode::NO_CONTENT)
}

pub async fn live(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Response, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    Ok(ws
        .on_upgrade(move |socket| notification_socket(socket, state, user_id))
        .into_response())
}

async fn notification_socket(mut socket: WebSocket, state: AppState, user_id: Uuid) {
    let mut events = state.notification_events.subscribe();
    loop {
        tokio::select! {
            incoming = socket.next() => {
                let Some(Ok(message)) = incoming else { break };
                match message {
                    Message::Close(_) => break,
                    Message::Ping(data) if socket.send(Message::Pong(data.clone())).await.is_err() => break,
                    _ => {}
                }
            }
            event = events.recv() => {
                match event {
                    Ok(event) if event.recipient_id == user_id => {
                        if let Ok(json) = serde_json::to_string(&event)
                            && socket.send(Message::Text(json.into())).await.is_err()
                        {
                            break;
                        }
                    }
                    Ok(_) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                }
            }
        }
    }
}

pub async fn emit(state: &AppState, draft: NotificationDraft) -> Result<(), AppError> {
    if draft.actor_id == Some(draft.recipient_id) {
        return Ok(());
    }
    let notification_id = Uuid::new_v4();
    let sql = r#"INSERT INTO notifications
           (id, recipient_id, actor_id, category, kind, title, body,
            entity_type, entity_id, action_path, payload, dedupe_key)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
           ON CONFLICT (recipient_id, dedupe_key) WHERE dedupe_key IS NOT NULL
           DO UPDATE SET actor_id = EXCLUDED.actor_id,
             category = EXCLUDED.category,
             kind = EXCLUDED.kind,
             title = EXCLUDED.title,
             body = EXCLUDED.body,
             entity_type = EXCLUDED.entity_type,
             entity_id = EXCLUDED.entity_id,
             action_path = EXCLUDED.action_path,
             payload = EXCLUDED.payload,
             read_at = NULL,
             created_at = NOW()
           RETURNING id"#;
    let inserted_id: Uuid = sqlx::query_scalar(sql)
        .bind(notification_id)
        .bind(draft.recipient_id)
        .bind(draft.actor_id)
        .bind(draft.category)
        .bind(draft.kind)
        .bind(draft.title)
        .bind(draft.body)
        .bind(draft.entity_type)
        .bind(draft.entity_id)
        .bind(draft.action_path)
        .bind(draft.payload)
        .bind(draft.dedupe_key)
        .fetch_one(&state.db)
        .await
        .map_err(AppError::internal)?;
    let notification = notification_by_id(state, draft.recipient_id, inserted_id).await?;
    let unread_count = unread_count(state, draft.recipient_id).await?;
    let _ = state.notification_events.send(NotificationRealtimeEvent {
        event: "notification".into(),
        recipient_id: draft.recipient_id,
        notification_id: Some(inserted_id),
        unread_count,
    });
    let delivery_state = state.clone();
    tokio::spawn(async move {
        deliver_push(
            &delivery_state,
            draft.recipient_id,
            notification,
            unread_count,
        )
        .await;
    });
    Ok(())
}

async fn notification_by_id(
    state: &AppState,
    user_id: Uuid,
    notification_id: Uuid,
) -> Result<NotificationResponse, AppError> {
    let sql = format!(
        "{NOTIFICATION_SELECT} WHERE notification.id = $1 AND notification.recipient_id = $2"
    );
    sqlx::query_as(&sql)
        .bind(notification_id)
        .bind(user_id)
        .fetch_optional(&state.db)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError::not_found("NOTIFICATION_NOT_FOUND", "Уведомление не найдено"))
}

async fn unread_count(state: &AppState, user_id: Uuid) -> Result<i64, AppError> {
    sqlx::query_scalar(
        "SELECT COUNT(*) FROM notifications WHERE recipient_id = $1 AND read_at IS NULL",
    )
    .bind(user_id)
    .fetch_one(&state.db)
    .await
    .map_err(AppError::internal)
}

pub async fn mark_entity_read(
    state: &AppState,
    user_id: Uuid,
    entity_type: &str,
    entity_id: Uuid,
) -> Result<(), AppError> {
    let changed = sqlx::query(
        "UPDATE notifications SET read_at = NOW() WHERE recipient_id = $1 AND entity_type = $2 AND entity_id = $3 AND read_at IS NULL",
    )
    .bind(user_id)
    .bind(entity_type)
    .bind(entity_id)
    .execute(&state.db)
    .await
    .map_err(AppError::internal)?;
    if changed.rows_affected() > 0 {
        broadcast_count(state, user_id, None, "readEntity").await?;
    }
    Ok(())
}

async fn broadcast_count(
    state: &AppState,
    user_id: Uuid,
    notification_id: Option<Uuid>,
    event: &str,
) -> Result<(), AppError> {
    let unread_count = unread_count(state, user_id).await?;
    let _ = state.notification_events.send(NotificationRealtimeEvent {
        event: event.into(),
        recipient_id: user_id,
        notification_id,
        unread_count,
    });
    Ok(())
}

async fn notification_settings(
    state: &AppState,
    user_id: Uuid,
) -> Result<NotificationSettingsResponse, AppError> {
    sqlx::query_as(
        r#"INSERT INTO notification_preferences (user_id) VALUES ($1)
           ON CONFLICT (user_id) DO UPDATE SET user_id = EXCLUDED.user_id
           RETURNING push_enabled, friend_requests, messages, invitations, activities, sound_enabled"#,
    )
    .bind(user_id)
    .fetch_one(&state.db)
    .await
    .map_err(AppError::internal)
}

async fn deliver_push(
    state: &AppState,
    user_id: Uuid,
    notification: NotificationResponse,
    badge: i64,
) {
    let Some(apns) = state.apns.clone() else {
        return;
    };
    let Ok(settings) = notification_settings(state, user_id).await else {
        return;
    };
    if !settings.push_enabled
        || !notification_push_enabled(&settings, &notification.category, &notification.kind)
    {
        return;
    }
    let Some(config) = state.config.apns.as_ref() else {
        return;
    };
    let devices: Vec<(Uuid, String)> = match sqlx::query_as(
        "SELECT id, token FROM push_devices WHERE user_id = $1 AND enabled = TRUE AND environment = $2 AND app_bundle = $3",
    )
    .bind(user_id)
    .bind(&config.environment)
    .bind(&config.bundle_id)
    .fetch_all(&state.db)
    .await
    {
        Ok(devices) => devices,
        Err(error) => {
            warn!(error = %error, %user_id, "unable to load push devices");
            return;
        }
    };
    for (device_id, token) in devices {
        let result = apns
            .send(
                &token,
                &ApnsPush {
                    notification_id: notification.id,
                    title: &notification.title,
                    body: &notification.body,
                    badge,
                    category: &notification.category,
                    kind: &notification.kind,
                    entity_type: notification.entity_type.as_deref(),
                    entity_id: notification.entity_id,
                    action_path: notification.action_path.as_deref(),
                    sound: settings.sound_enabled,
                },
            )
            .await;
        match result {
            Ok(()) => {
                info!(%user_id, %device_id, notification_id = %notification.id, "APNs push delivered")
            }
            Err(ApnsError::InvalidToken) => {
                if let Err(error) =
                    sqlx::query("UPDATE push_devices SET enabled = FALSE WHERE id = $1")
                        .bind(device_id)
                        .execute(&state.db)
                        .await
                {
                    warn!(error = %error, %device_id, "unable to disable invalid APNs token");
                }
            }
            Err(error) => warn!(error = %error, %user_id, %device_id, "APNs push failed"),
        }
    }
}

fn notification_push_enabled(
    settings: &NotificationSettingsResponse,
    category: &str,
    kind: &str,
) -> bool {
    match (category, kind) {
        ("social", "friend_request" | "friend_accepted") => settings.friend_requests,
        (
            "social",
            "invitation" | "invitation_accepted" | "invitation_declined" | "invitation_countered",
        ) => settings.invitations,
        ("messages", "new_message") => settings.messages,
        ("activities", _) => settings.activities,
        ("system", "system") => true,
        _ => false,
    }
}

pub fn spawn_activity_reminder_worker(state: AppState) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(StdDuration::from_secs(300));
        loop {
            interval.tick().await;
            if let Err(error) = enqueue_activity_reminders(&state).await {
                warn!(error = ?error, "activity reminder worker failed");
            }
        }
    });
}

async fn enqueue_activity_reminders(state: &AppState) -> Result<(), AppError> {
    let rows: Vec<(Uuid, Uuid, Uuid, String)> = sqlx::query_as(
        r#"SELECT activity.id, recipient.user_id, activity.creator_id, activity.title
           FROM activities activity
           CROSS JOIN LATERAL (
             SELECT activity.creator_id AS user_id
             UNION
             SELECT application.applicant_id FROM activity_applications application
             WHERE application.activity_id = activity.id AND application.status = 'accepted'
           ) recipient
           WHERE activity.status IN ('published', 'full', 'scheduled')
             AND activity.starts_at BETWEEN NOW() + INTERVAL '50 minutes' AND NOW() + INTERVAL '70 minutes'"#,
    )
    .fetch_all(&state.db)
    .await
    .map_err(AppError::internal)?;
    for (activity_id, recipient_id, _organizer_id, title) in rows {
        emit(
            state,
            NotificationDraft {
                recipient_id,
                actor_id: None,
                category: "activities",
                kind: "activity_reminder",
                title: "Скоро начало".into(),
                body: format!("«{title}» начнётся примерно через час"),
                entity_type: Some("activity"),
                entity_id: Some(activity_id),
                action_path: Some(format!("gonow://activities/{activity_id}")),
                payload: serde_json::json!({}),
                dedupe_key: Some(format!("activity-reminder:{activity_id}:{recipient_id}")),
            },
        )
        .await?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn notification_categories_map_to_user_preferences() {
        let settings = NotificationSettingsResponse {
            push_enabled: true,
            friend_requests: true,
            messages: false,
            invitations: false,
            activities: true,
            sound_enabled: true,
        };
        assert!(notification_push_enabled(
            &settings,
            "social",
            "friend_request"
        ));
        assert!(!notification_push_enabled(
            &settings,
            "social",
            "invitation"
        ));
        assert!(!notification_push_enabled(
            &settings,
            "messages",
            "new_message"
        ));
        assert!(notification_push_enabled(
            &settings,
            "activities",
            "activity_updated"
        ));
        assert!(notification_push_enabled(&settings, "system", "system"));
    }
}
