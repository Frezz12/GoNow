use axum::{
    Json,
    body::Body,
    extract::{
        Multipart, Path, Query, State, WebSocketUpgrade,
        ws::{Message, WebSocket},
    },
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use chrono::{DateTime, Duration, Utc};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, Postgres, Transaction};
use std::collections::HashSet;
use tracing::warn;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::{
    app::AppState,
    infrastructure::cache,
    shared::{errors::AppError, response::ApiResponse},
};

use super::{
    notifications::{self, NotificationDraft},
    users::active_user_id,
};

pub const MAX_CHAT_ATTACHMENT_BYTES: usize = 50 * 1024 * 1024;
pub const MAX_CHAT_MULTIPART_BODY_BYTES: usize = MAX_CHAT_ATTACHMENT_BYTES + 256 * 1024;
const MAX_CHAT_AVATAR_BYTES: usize = 5 * 1024 * 1024;
const CHAT_ATTACHMENT_CACHE_CONTROL: &str = "private, max-age=604800, immutable";

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct PrivacySettingsResponse {
    pub message_privacy: String,
    pub invitation_privacy: String,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UpdatePrivacyRequest {
    pub message_privacy: String,
    pub invitation_privacy: String,
}

#[derive(Debug, Deserialize)]
pub struct DiscoverQuery {
    pub q: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct SocialUserResponse {
    pub id: Uuid,
    pub display_name: String,
    pub username: String,
    pub city: Option<String>,
    pub bio: Option<String>,
    pub interests: Vec<String>,
    pub avatar_path: Option<String>,
    pub friendship_status: String,
    pub is_incoming_request: bool,
    pub can_message: bool,
    pub can_invite: bool,
}

#[derive(FromRow)]
struct SocialUserRow {
    id: Uuid,
    display_name: String,
    username: String,
    city: Option<String>,
    bio: Option<String>,
    interests: Vec<String>,
    avatar_id: Option<Uuid>,
    friendship_status: Option<String>,
    requested_by: Option<Uuid>,
    message_privacy: String,
    invitation_privacy: String,
    viewer_verified: bool,
}

impl SocialUserRow {
    fn into_response(self, viewer_id: Uuid) -> SocialUserResponse {
        let accepted = self.friendship_status.as_deref() == Some("accepted");
        let can_message = match self.message_privacy.as_str() {
            "everyone" => true,
            "friends" => accepted,
            _ => false,
        };
        let can_invite = match self.invitation_privacy.as_str() {
            "everyone" => true,
            "friends" => accepted,
            "verified" => self.viewer_verified,
            _ => false,
        };
        SocialUserResponse {
            id: self.id,
            display_name: self.display_name,
            username: self.username,
            city: self.city,
            bio: self.bio,
            interests: self.interests,
            avatar_path: self
                .avatar_id
                .map(|id| format!("users/photos/{id}/content")),
            friendship_status: self.friendship_status.unwrap_or_else(|| "none".into()),
            is_incoming_request: self.requested_by.is_some_and(|id| id != viewer_id),
            can_message,
            can_invite,
        }
    }
}

const SOCIAL_USER_SELECT: &str = r#"
SELECT u.id, u.display_name, u.username, u.city, u.bio, u.interests,
       (SELECT photo.id FROM user_photos photo WHERE photo.user_id = u.id AND photo.is_current_avatar = TRUE LIMIT 1) AS avatar_id,
       friendship.status AS friendship_status, friendship.requested_by,
       u.message_privacy, u.invitation_privacy,
       (SELECT email_verified FROM users WHERE id = $1) AS viewer_verified
FROM users u
LEFT JOIN friendships friendship
  ON friendship.user_low = LEAST($1, u.id)
 AND friendship.user_high = GREATEST($1, u.id)
WHERE u.id <> $1 AND u.status = 'active'
"#;

async fn social_user(
    state: &AppState,
    viewer_id: Uuid,
    user_id: Uuid,
) -> Result<SocialUserResponse, AppError> {
    let query = format!("{SOCIAL_USER_SELECT} AND u.id = $2");
    let row: Option<SocialUserRow> = sqlx::query_as(&query)
        .bind(viewer_id)
        .bind(user_id)
        .fetch_optional(&state.db)
        .await
        .map_err(AppError::internal)?;
    row.map(|row| row.into_response(viewer_id))
        .ok_or_else(|| AppError {
            status: StatusCode::NOT_FOUND,
            code: "PROFILE_NOT_FOUND",
            message: "Профиль не найден".into(),
            fields: None,
        })
}

pub async fn privacy(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<PrivacySettingsResponse>>, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    let row: (String, String) =
        sqlx::query_as("SELECT message_privacy, invitation_privacy FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_one(&state.db)
            .await
            .map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(PrivacySettingsResponse {
        message_privacy: row.0,
        invitation_privacy: row.1,
    })))
}

pub async fn update_privacy(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<UpdatePrivacyRequest>,
) -> Result<Json<ApiResponse<PrivacySettingsResponse>>, AppError> {
    if !matches!(
        request.message_privacy.as_str(),
        "everyone" | "friends" | "nobody"
    ) || !matches!(
        request.invitation_privacy.as_str(),
        "everyone" | "friends" | "verified" | "nobody"
    ) {
        return Err(AppError::validation(serde_json::json!({
            "privacy": "Выберите доступный вариант конфиденциальности"
        })));
    }
    let user_id = active_user_id(&headers, &state).await?;
    let row: (String, String) = sqlx::query_as(
        "UPDATE users SET message_privacy = $2, invitation_privacy = $3, updated_at = NOW() WHERE id = $1 RETURNING message_privacy, invitation_privacy",
    )
    .bind(user_id)
    .bind(request.message_privacy)
    .bind(request.invitation_privacy)
    .fetch_one(&state.db)
    .await
    .map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(PrivacySettingsResponse {
        message_privacy: row.0,
        invitation_privacy: row.1,
    })))
}

pub async fn discover(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<DiscoverQuery>,
) -> Result<Json<ApiResponse<Vec<SocialUserResponse>>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let search = query
        .q
        .unwrap_or_default()
        .trim()
        .trim_start_matches('@')
        .to_ascii_lowercase();
    let sql = format!(
        "{SOCIAL_USER_SELECT} AND ($2 = '' OR u.username LIKE '%' || $2 || '%' OR LOWER(u.display_name) LIKE '%' || $2 || '%' OR LOWER(COALESCE(u.city, '')) LIKE '%' || $2 || '%') ORDER BY CASE WHEN u.username = $2 THEN 0 WHEN friendship.status = 'accepted' THEN 1 WHEN friendship.status = 'pending' THEN 2 ELSE 3 END, u.display_name LIMIT 50"
    );
    let rows: Vec<SocialUserRow> = sqlx::query_as(&sql)
        .bind(viewer_id)
        .bind(search)
        .fetch_all(&state.db)
        .await
        .map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(
        rows.into_iter()
            .map(|row| row.into_response(viewer_id))
            .collect(),
    )))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct TargetUserRequest {
    pub user_id: Uuid,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct FriendDecisionRequest {
    pub action: String,
}

pub async fn request_friend(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<TargetUserRequest>,
) -> Result<(StatusCode, Json<ApiResponse<SocialUserResponse>>), AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    if viewer_id == request.user_id {
        return Err(AppError::validation(
            serde_json::json!({"userId": "Нельзя добавить себя в друзья"}),
        ));
    }
    let _ = social_user(&state, viewer_id, request.user_id).await?;
    let (low, high) = ordered_pair(viewer_id, request.user_id);
    let changed = sqlx::query(
        "INSERT INTO friendships (user_low, user_high, requested_by, status) VALUES ($1, $2, $3, 'pending') ON CONFLICT (user_low, user_high) DO UPDATE SET requested_by = EXCLUDED.requested_by, status = 'pending', updated_at = NOW() WHERE friendships.status <> 'accepted'",
    )
    .bind(low)
    .bind(high)
    .bind(viewer_id)
    .execute(&state.db)
    .await
    .map_err(AppError::internal)?;
    if changed.rows_affected() > 0 {
        let actor_name = user_display_name(&state, viewer_id).await?;
        notifications::emit(
            &state,
            NotificationDraft {
                recipient_id: request.user_id,
                actor_id: Some(viewer_id),
                category: "social",
                kind: "friend_request",
                title: "Новая заявка в друзья".into(),
                body: format!("{actor_name} хочет добавить вас в друзья"),
                entity_type: Some("user"),
                entity_id: Some(viewer_id),
                action_path: Some(format!("gonow://people/{viewer_id}")),
                payload: serde_json::json!({}),
                dedupe_key: Some(format!("friend-request:{viewer_id}:{}", request.user_id)),
            },
        )
        .await?;
    }
    Ok((
        StatusCode::CREATED,
        Json(ApiResponse::new(
            social_user(&state, viewer_id, request.user_id).await?,
        )),
    ))
}

pub async fn decide_friend(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(user_id): Path<Uuid>,
    Json(request): Json<FriendDecisionRequest>,
) -> Result<Json<ApiResponse<SocialUserResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let status = match request.action.as_str() {
        "accept" => "accepted",
        "decline" => "declined",
        _ => {
            return Err(AppError::validation(
                serde_json::json!({"action": "Выберите принять или отклонить"}),
            ));
        }
    };
    let (low, high) = ordered_pair(viewer_id, user_id);
    let changed = sqlx::query(
        "UPDATE friendships SET status = $4, updated_at = NOW() WHERE user_low = $1 AND user_high = $2 AND requested_by <> $3 AND status = 'pending'",
    )
    .bind(low)
    .bind(high)
    .bind(viewer_id)
    .bind(status)
    .execute(&state.db)
    .await
    .map_err(AppError::internal)?;
    if changed.rows_affected() == 0 {
        return Err(AppError {
            status: StatusCode::CONFLICT,
            code: "FRIEND_REQUEST_NOT_PENDING",
            message: "Заявка уже обработана".into(),
            fields: None,
        });
    }
    notifications::resolve_entity_action(&state, viewer_id, "user", user_id, status).await?;
    if status == "accepted" {
        let actor_name = user_display_name(&state, viewer_id).await?;
        notifications::emit(
            &state,
            NotificationDraft {
                recipient_id: user_id,
                actor_id: Some(viewer_id),
                category: "social",
                kind: "friend_accepted",
                title: "Заявка принята".into(),
                body: format!("{actor_name} теперь у вас в друзьях"),
                entity_type: Some("user"),
                entity_id: Some(viewer_id),
                action_path: Some(format!("gonow://people/{viewer_id}")),
                payload: serde_json::json!({}),
                dedupe_key: Some(format!("friend-accepted:{viewer_id}:{user_id}")),
            },
        )
        .await?;
    }
    Ok(Json(ApiResponse::new(
        social_user(&state, viewer_id, user_id).await?,
    )))
}

pub async fn remove_friend(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(user_id): Path<Uuid>,
) -> Result<Json<ApiResponse<SocialUserResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let (low, high) = ordered_pair(viewer_id, user_id);
    sqlx::query("DELETE FROM friendships WHERE user_low = $1 AND user_high = $2")
        .bind(low)
        .bind(high)
        .execute(&state.db)
        .await
        .map_err(AppError::internal)?;
    notifications::resolve_entity_action(&state, user_id, "user", viewer_id, "cancelled").await?;
    Ok(Json(ApiResponse::new(
        social_user(&state, viewer_id, user_id).await?,
    )))
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CreateInvitationRequest {
    pub recipient_id: Uuid,
    pub activity_id: Option<Uuid>,
    pub template: String,
    pub proposed_at: Option<DateTime<Utc>>,
    pub place: Option<String>,
    pub message: Option<String>,
    pub expires_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct InvitationDecisionRequest {
    pub action: String,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct InvitationResponse {
    pub id: Uuid,
    pub sender_id: Uuid,
    pub sender_name: String,
    pub recipient_id: Uuid,
    pub recipient_name: String,
    pub activity_id: Option<Uuid>,
    pub conversation_id: Option<Uuid>,
    pub template: String,
    pub proposed_at: Option<DateTime<Utc>>,
    pub place: Option<String>,
    pub message: Option<String>,
    pub status: String,
    pub expires_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub is_incoming: bool,
}

const INVITATION_SELECT: &str = r#"
SELECT invitation.id, invitation.sender_id, sender.display_name AS sender_name,
       invitation.recipient_id, recipient.display_name AS recipient_name,
       invitation.activity_id, invitation.conversation_id, invitation.template,
       invitation.proposed_at, invitation.place, invitation.message,
       CASE WHEN invitation.status = 'pending' AND invitation.expires_at <= NOW() THEN 'expired' ELSE invitation.status END AS status,
       invitation.expires_at, invitation.created_at,
       (invitation.recipient_id = $1) AS is_incoming
FROM meeting_invitations invitation
JOIN users sender ON sender.id = invitation.sender_id
JOIN users recipient ON recipient.id = invitation.recipient_id
"#;

pub async fn invitations(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<Vec<InvitationResponse>>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    sqlx::query("UPDATE meeting_invitations SET status = 'expired', updated_at = NOW() WHERE status = 'pending' AND expires_at <= NOW()")
        .execute(&state.db)
        .await
        .map_err(AppError::internal)?;
    let sql = format!(
        "{INVITATION_SELECT} WHERE invitation.sender_id = $1 OR invitation.recipient_id = $1 ORDER BY invitation.created_at DESC LIMIT 100"
    );
    let rows = sqlx::query_as(&sql)
        .bind(viewer_id)
        .fetch_all(&state.db)
        .await
        .map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(rows)))
}

pub async fn create_invitation(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<CreateInvitationRequest>,
) -> Result<(StatusCode, Json<ApiResponse<InvitationResponse>>), AppError> {
    let sender_id = active_user_id(&headers, &state).await?;
    let allowed_templates = [
        "walk", "coffee", "cinema", "dinner", "bicycle", "games", "concert", "talk", "activity",
    ];
    if !allowed_templates.contains(&request.template.as_str())
        || request
            .place
            .as_ref()
            .is_some_and(|value| value.chars().count() > 180)
        || request
            .message
            .as_ref()
            .is_some_and(|value| value.chars().count() > 500)
    {
        return Err(AppError::validation(serde_json::json!({
            "invitation": "Проверьте формат приглашения"
        })));
    }
    let target = social_user(&state, sender_id, request.recipient_id).await?;
    if !target.can_invite {
        return Err(AppError {
            status: StatusCode::FORBIDDEN,
            code: "INVITATIONS_NOT_ALLOWED",
            message: "Пользователь ограничил приглашения".into(),
            fields: None,
        });
    }
    let today_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM meeting_invitations WHERE sender_id = $1 AND created_at >= NOW() - INTERVAL '24 hours'",
    )
    .bind(sender_id)
    .fetch_one(&state.db)
    .await
    .map_err(AppError::internal)?;
    if today_count >= 10 {
        return Err(AppError {
            status: StatusCode::TOO_MANY_REQUESTS,
            code: "INVITATION_DAILY_LIMIT",
            message: "Сегодня уже отправлено 10 приглашений".into(),
            fields: None,
        });
    }
    let pending: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM meeting_invitations WHERE LEAST(sender_id, recipient_id) = LEAST($1, $2) AND GREATEST(sender_id, recipient_id) = GREATEST($1, $2) AND status = 'pending' AND expires_at > NOW())",
    )
    .bind(sender_id)
    .bind(request.recipient_id)
    .fetch_one(&state.db)
    .await
    .map_err(AppError::internal)?;
    if pending {
        return Err(AppError {
            status: StatusCode::CONFLICT,
            code: "INVITATION_ALREADY_PENDING",
            message: "Между вами уже есть активное приглашение".into(),
            fields: None,
        });
    }
    let expires_at = request
        .expires_at
        .unwrap_or_else(|| Utc::now() + Duration::hours(24))
        .min(Utc::now() + Duration::days(7));
    if expires_at <= Utc::now() {
        return Err(AppError::validation(
            serde_json::json!({"expiresAt": "Срок приглашения должен быть в будущем"}),
        ));
    }
    let id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();
    let sender_name = user_display_name(&state, sender_id).await?;
    let template = request.template;
    let proposed_at = request.proposed_at;
    let place = clean(request.place);
    let message = clean(request.message);
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    sqlx::query("INSERT INTO conversations (id, kind, title) VALUES ($1, 'meeting', $2)")
        .bind(conversation_id)
        .bind(format!("Встреча · {}", template_title(&template)))
        .execute(&mut *tx)
        .await
        .map_err(AppError::internal)?;
    add_member(&mut tx, conversation_id, sender_id).await?;
    add_member(&mut tx, conversation_id, request.recipient_id).await?;
    sqlx::query(
        "INSERT INTO meeting_invitations (id, sender_id, recipient_id, activity_id, conversation_id, template, proposed_at, place, message, expires_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)",
    )
    .bind(id)
    .bind(sender_id)
    .bind(request.recipient_id)
    .bind(request.activity_id)
    .bind(conversation_id)
    .bind(&template)
    .bind(proposed_at)
    .bind(&place)
    .bind(&message)
    .bind(expires_at)
    .execute(&mut *tx)
    .await
    .map_err(AppError::internal)?;
    sqlx::query(
        "INSERT INTO chat_messages (id, conversation_id, sender_id, kind, body) VALUES ($1,$2,$3,'invitation',$4)",
    )
    .bind(Uuid::new_v4())
    .bind(conversation_id)
    .bind(sender_id)
    .bind(invitation_chat_body(
        &sender_name,
        &template,
        proposed_at,
        place.as_deref(),
        message.as_deref(),
    ))
    .execute(&mut *tx)
    .await
    .map_err(AppError::internal)?;
    tx.commit().await.map_err(AppError::internal)?;
    let invitation = invitation_by_id(&state, sender_id, id).await?;
    notifications::emit(
        &state,
        NotificationDraft {
            recipient_id: invitation.recipient_id,
            actor_id: Some(sender_id),
            category: "social",
            kind: "invitation",
            title: format!("Приглашение: {}", template_title(&invitation.template)),
            body: format!("{} приглашает вас встретиться", invitation.sender_name),
            entity_type: Some("invitation"),
            entity_id: Some(invitation.id),
            action_path: Some(format!("gonow://invitations/{}", invitation.id)),
            payload: serde_json::json!({"template": invitation.template}),
            dedupe_key: Some(format!("invitation:{}", invitation.id)),
        },
    )
    .await?;
    Ok((StatusCode::CREATED, Json(ApiResponse::new(invitation))))
}

pub async fn decide_invitation(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(invitation_id): Path<Uuid>,
    Json(request): Json<InvitationDecisionRequest>,
) -> Result<Json<ApiResponse<InvitationResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let status = match request.action.as_str() {
        "accept" => "accepted",
        "decline" => "declined",
        "counter" => "countered",
        _ => {
            return Err(AppError::validation(
                serde_json::json!({"action": "Неизвестный ответ на приглашение"}),
            ));
        }
    };
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    let parties: Option<(Uuid, Uuid, String, Option<Uuid>)> = sqlx::query_as(
        "SELECT sender_id, recipient_id, template, conversation_id FROM meeting_invitations WHERE id = $1 AND recipient_id = $2 AND status = 'pending' AND expires_at > NOW() FOR UPDATE",
    )
    .bind(invitation_id)
    .bind(viewer_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(AppError::internal)?;
    let (sender_id, recipient_id, template, existing_conversation_id) =
        parties.ok_or_else(|| AppError {
            status: StatusCode::CONFLICT,
            code: "INVITATION_NOT_PENDING",
            message: "Приглашение уже обработано или истекло".into(),
            fields: None,
        })?;
    let conversation_id = if let Some(conversation_id) = existing_conversation_id {
        conversation_id
    } else {
        let conversation_id = Uuid::new_v4();
        sqlx::query("INSERT INTO conversations (id, kind, title) VALUES ($1, 'meeting', $2)")
            .bind(conversation_id)
            .bind(format!("Встреча · {}", template_title(&template)))
            .execute(&mut *tx)
            .await
            .map_err(AppError::internal)?;
        add_member(&mut tx, conversation_id, sender_id).await?;
        add_member(&mut tx, conversation_id, recipient_id).await?;
        conversation_id
    };
    let status_message = match status {
        "accepted" => "Приглашение принято. Теперь выберите удобные место и время вместе.",
        "countered" => "Предложено изменить место или время встречи.",
        _ => "Приглашение отклонено.",
    };
    sqlx::query("INSERT INTO chat_messages (id, conversation_id, sender_id, kind, body) VALUES ($1,$2,$3,'system',$4)")
        .bind(Uuid::new_v4())
        .bind(conversation_id)
        .bind(viewer_id)
        .bind(status_message)
        .execute(&mut *tx)
        .await
        .map_err(AppError::internal)?;
    sqlx::query("UPDATE meeting_invitations SET status = $2, conversation_id = $3, updated_at = NOW() WHERE id = $1")
        .bind(invitation_id)
        .bind(status)
        .bind(Some(conversation_id))
        .execute(&mut *tx)
        .await
        .map_err(AppError::internal)?;
    tx.commit().await.map_err(AppError::internal)?;
    notifications::resolve_entity_action(&state, viewer_id, "invitation", invitation_id, status)
        .await?;
    let invitation = invitation_by_id(&state, viewer_id, invitation_id).await?;
    notifications::emit(
        &state,
        NotificationDraft {
            recipient_id: sender_id,
            actor_id: Some(viewer_id),
            category: "social",
            kind: match status {
                "accepted" => "invitation_accepted",
                "countered" => "invitation_countered",
                _ => "invitation_declined",
            },
            title: match status {
                "accepted" => "Приглашение принято".into(),
                "countered" => "Предложен другой вариант".into(),
                _ => "Ответ на приглашение".into(),
            },
            body: match status {
                "accepted" => format!("{} согласился встретиться", invitation.recipient_name),
                "countered" => format!(
                    "{} предложил изменить место или время",
                    invitation.recipient_name
                ),
                _ => format!("{} не сможет присоединиться", invitation.recipient_name),
            },
            entity_type: Some("conversation"),
            entity_id: Some(conversation_id),
            action_path: Some(format!("gonow://chats/{conversation_id}")),
            payload: serde_json::json!({"status": status}),
            dedupe_key: Some(format!("invitation-response:{invitation_id}:{status}")),
        },
    )
    .await?;
    Ok(Json(ApiResponse::new(invitation)))
}

async fn invitation_by_id(
    state: &AppState,
    viewer_id: Uuid,
    id: Uuid,
) -> Result<InvitationResponse, AppError> {
    let sql = format!(
        "{INVITATION_SELECT} WHERE invitation.id = $2 AND (invitation.sender_id = $1 OR invitation.recipient_id = $1)"
    );
    sqlx::query_as(&sql)
        .bind(viewer_id)
        .bind(id)
        .fetch_optional(&state.db)
        .await
        .map_err(AppError::internal)?
        .ok_or_else(|| AppError {
            status: StatusCode::NOT_FOUND,
            code: "INVITATION_NOT_FOUND",
            message: "Приглашение не найдено".into(),
            fields: None,
        })
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ConversationResponse {
    pub id: Uuid,
    pub kind: String,
    pub title: String,
    pub participant_id: Option<Uuid>,
    pub avatar_path: Option<String>,
    pub activity_id: Option<Uuid>,
    pub created_by_id: Option<Uuid>,
    pub last_message: Option<String>,
    pub last_message_at: Option<DateTime<Utc>>,
    pub unread_count: i64,
    pub member_count: i64,
    pub is_archived: bool,
    pub is_online: bool,
    pub last_seen_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ConversationMemberResponse {
    pub id: Uuid,
    pub display_name: String,
    pub avatar_path: Option<String>,
    pub is_creator: bool,
    pub is_friend: bool,
    pub is_online: bool,
    pub last_seen_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ConversationDetailsResponse {
    pub conversation: ConversationResponse,
    pub members: Vec<ConversationMemberResponse>,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ConversationInvitationResponse {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub conversation_title: String,
    pub inviter_id: Uuid,
    pub inviter_name: String,
    pub status: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CreateGroupRequest {
    pub title: String,
    #[serde(default)]
    pub member_ids: Vec<Uuid>,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ArchiveConversationRequest {
    pub archived: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AddConversationMemberRequest {
    pub user_id: Uuid,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AddConversationMemberResponse {
    pub status: String,
}

#[derive(Clone, Debug, Serialize, FromRow, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ChatMessageResponse {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    pub sender_name: String,
    pub kind: String,
    pub body: String,
    pub proposal_detail: Option<String>,
    pub vote_count: i64,
    pub is_voted: bool,
    pub is_mine: bool,
    pub is_read: bool,
    pub reply_to_id: Option<Uuid>,
    pub reply_to_sender_name: Option<String>,
    pub reply_to_body: Option<String>,
    pub reply_to_kind: Option<String>,
    pub attachment_name: Option<String>,
    pub attachment_content_type: Option<String>,
    pub attachment_bytes: Option<i32>,
    pub duration_seconds: Option<f64>,
    pub content_path: Option<String>,
    pub edited_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatRealtimeEvent {
    pub event: String,
    pub conversation_id: Uuid,
    pub message_id: Option<Uuid>,
    pub user_id: Option<Uuid>,
}

#[derive(Debug, Deserialize)]
struct ChatSocketCommand {
    event: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AttachmentUploadQuery {
    pub kind: String,
    pub duration_seconds: Option<f64>,
    pub reply_to_id: Option<Uuid>,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct SendMessageRequest {
    pub kind: String,
    pub body: String,
    pub proposal_detail: Option<String>,
    pub reply_to_id: Option<Uuid>,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct EditMessageRequest {
    pub body: String,
}

pub async fn conversations(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<Vec<ConversationResponse>>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let rows: Vec<ConversationResponse> = sqlx::query_as(
        r#"SELECT conversation.id, conversation.kind,
                  COALESCE(conversation.title, other.display_name, 'Чат') AS title,
                  other.id AS participant_id,
                  CASE
                      WHEN conversation.avatar_object_key IS NOT NULL THEN 'social/conversations/' || conversation.id || '/avatar'
                      WHEN activity_avatar.id IS NOT NULL THEN 'activities/' || conversation.activity_id || '/photos/' || activity_avatar.id || '/content'
                      WHEN avatar.id IS NOT NULL THEN 'users/photos/' || avatar.id || '/content'
                      ELSE NULL
                  END AS avatar_path,
                  conversation.activity_id, conversation.created_by AS created_by_id,
                  last_message.body AS last_message, last_message.created_at AS last_message_at,
                  (SELECT COUNT(*) FROM chat_messages unread WHERE unread.conversation_id = conversation.id AND unread.sender_id <> $1 AND unread.created_at > COALESCE(member.last_read_at, member.joined_at)) AS unread_count,
                  (SELECT COUNT(*) FROM conversation_members participant WHERE participant.conversation_id = conversation.id) AS member_count,
                  (member.archived_at IS NOT NULL) AS is_archived,
                  COALESCE(other.last_seen_at > NOW() - INTERVAL '2 minutes', FALSE) AS is_online,
                  other.last_seen_at
           FROM conversation_members member
           JOIN conversations conversation ON conversation.id = member.conversation_id
           LEFT JOIN LATERAL (
               SELECT users.id, users.display_name, users.last_seen_at FROM conversation_members others
               JOIN users ON users.id = others.user_id
               WHERE others.conversation_id = conversation.id AND others.user_id <> $1 LIMIT 1
           ) other ON TRUE
           LEFT JOIN LATERAL (
               SELECT id FROM user_photos WHERE user_id = other.id AND is_current_avatar = TRUE LIMIT 1
           ) avatar ON TRUE
           LEFT JOIN LATERAL (
               SELECT id FROM activity_photos WHERE activity_id = conversation.activity_id ORDER BY is_cover DESC, sort_index LIMIT 1
           ) activity_avatar ON TRUE
           LEFT JOIN LATERAL (
               SELECT body, created_at FROM chat_messages WHERE conversation_id = conversation.id ORDER BY created_at DESC LIMIT 1
           ) last_message ON TRUE
           WHERE member.user_id = $1
           ORDER BY COALESCE(last_message.created_at, conversation.created_at) DESC"#,
    )
    .bind(viewer_id)
    .fetch_all(&state.db)
    .await
    .map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(rows)))
}

pub async fn create_direct_conversation(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<TargetUserRequest>,
) -> Result<(StatusCode, Json<ApiResponse<ConversationResponse>>), AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let target = social_user(&state, viewer_id, request.user_id).await?;
    if !target.can_message {
        return Err(AppError {
            status: StatusCode::FORBIDDEN,
            code: "MESSAGES_NOT_ALLOWED",
            message: "Пользователь принимает сообщения только по своим настройкам".into(),
            fields: None,
        });
    }
    let direct_key = ordered_pair_key(viewer_id, request.user_id);
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    let conversation_id: Uuid = sqlx::query_scalar(
        "INSERT INTO conversations (id, kind, direct_key) VALUES ($1, 'direct', $2) ON CONFLICT (direct_key) DO UPDATE SET updated_at = NOW() RETURNING id",
    )
    .bind(Uuid::new_v4())
    .bind(direct_key)
    .fetch_one(&mut *tx)
    .await
    .map_err(AppError::internal)?;
    add_member(&mut tx, conversation_id, viewer_id).await?;
    add_member(&mut tx, conversation_id, request.user_id).await?;
    tx.commit().await.map_err(AppError::internal)?;
    let conversation = conversation_by_id(&state, viewer_id, conversation_id).await?;
    Ok((StatusCode::CREATED, Json(ApiResponse::new(conversation))))
}

pub async fn create_group_conversation(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<CreateGroupRequest>,
) -> Result<(StatusCode, Json<ApiResponse<ConversationResponse>>), AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let title = request.title.trim();
    if !(2..=70).contains(&title.chars().count()) {
        return Err(AppError::validation(
            serde_json::json!({"title": "Название должно содержать от 2 до 70 символов"}),
        ));
    }
    let member_ids: HashSet<_> = request
        .member_ids
        .into_iter()
        .filter(|id| *id != viewer_id)
        .collect();
    if member_ids.len() > 99 {
        return Err(AppError::validation(
            serde_json::json!({"memberIds": "В группе может быть не больше 100 участников"}),
        ));
    }

    let conversation_id = Uuid::new_v4();
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    sqlx::query(
        "INSERT INTO conversations (id, kind, title, created_by) VALUES ($1, 'group', $2, $3)",
    )
    .bind(conversation_id)
    .bind(title)
    .bind(viewer_id)
    .execute(&mut *tx)
    .await
    .map_err(AppError::internal)?;
    add_member(&mut tx, conversation_id, viewer_id).await?;
    for user_id in member_ids {
        add_friend_or_invite(&mut tx, conversation_id, viewer_id, user_id).await?;
    }
    tx.commit().await.map_err(AppError::internal)?;
    let conversation = conversation_by_id(&state, viewer_id, conversation_id).await?;
    Ok((StatusCode::CREATED, Json(ApiResponse::new(conversation))))
}

pub async fn conversation_details(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(conversation_id): Path<Uuid>,
) -> Result<Json<ApiResponse<ConversationDetailsResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let conversation = conversation_by_id(&state, viewer_id, conversation_id).await?;
    let members: Vec<ConversationMemberResponse> = sqlx::query_as(
        r#"SELECT users.id, users.display_name,
                  CASE WHEN avatar.id IS NULL THEN NULL ELSE 'users/photos/' || avatar.id || '/content' END AS avatar_path,
                  (users.id = conversation.created_by) AS is_creator,
                  EXISTS(SELECT 1 FROM friendships friendship WHERE friendship.status = 'accepted' AND ((friendship.user_low = $2 AND friendship.user_high = users.id) OR (friendship.user_high = $2 AND friendship.user_low = users.id))) AS is_friend,
                  (users.last_seen_at > NOW() - INTERVAL '2 minutes') AS is_online,
                  users.last_seen_at
           FROM conversation_members member
           JOIN users ON users.id = member.user_id
           JOIN conversations conversation ON conversation.id = member.conversation_id
           LEFT JOIN LATERAL (SELECT id FROM user_photos WHERE user_id = users.id AND is_current_avatar = TRUE LIMIT 1) avatar ON TRUE
           WHERE member.conversation_id = $1
           ORDER BY (users.id = conversation.created_by) DESC, users.display_name"#,
    )
    .bind(conversation_id)
    .bind(viewer_id)
    .fetch_all(&state.db)
    .await
    .map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(ConversationDetailsResponse {
        conversation,
        members,
    })))
}

pub async fn archive_conversation(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(conversation_id): Path<Uuid>,
    Json(request): Json<ArchiveConversationRequest>,
) -> Result<Json<ApiResponse<ConversationResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_member(&state, conversation_id, viewer_id).await?;
    sqlx::query(
        "UPDATE conversation_members SET archived_at = CASE WHEN $3 THEN NOW() ELSE NULL END WHERE conversation_id = $1 AND user_id = $2",
    )
    .bind(conversation_id)
    .bind(viewer_id)
    .bind(request.archived)
    .execute(&state.db)
    .await
    .map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(
        conversation_by_id(&state, viewer_id, conversation_id).await?,
    )))
}

pub async fn add_conversation_member(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(conversation_id): Path<Uuid>,
    Json(request): Json<AddConversationMemberRequest>,
) -> Result<Json<ApiResponse<AddConversationMemberResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_conversation_creator(&state, conversation_id, viewer_id).await?;
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    let added = add_friend_or_invite(&mut tx, conversation_id, viewer_id, request.user_id).await?;
    tx.commit().await.map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(AddConversationMemberResponse {
        status: if added { "added" } else { "invited" }.into(),
    })))
}

pub async fn conversation_invitations(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<Vec<ConversationInvitationResponse>>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let rows = sqlx::query_as(
        r#"SELECT invitation.id, invitation.conversation_id,
                  COALESCE(conversation.title, 'Групповой чат') AS conversation_title,
                  invitation.inviter_id, inviter.display_name AS inviter_name,
                  invitation.status, invitation.created_at
           FROM conversation_invitations invitation
           JOIN conversations conversation ON conversation.id = invitation.conversation_id
           JOIN users inviter ON inviter.id = invitation.inviter_id
           WHERE invitation.invitee_id = $1 AND invitation.status = 'pending'
           ORDER BY invitation.created_at DESC"#,
    )
    .bind(viewer_id)
    .fetch_all(&state.db)
    .await
    .map_err(AppError::internal)?;
    Ok(Json(ApiResponse::new(rows)))
}

pub async fn decide_conversation_invitation(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(invitation_id): Path<Uuid>,
    Json(request): Json<InvitationDecisionRequest>,
) -> Result<Json<ApiResponse<ConversationInvitationResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    let status = match request.action.as_str() {
        "accept" => "accepted",
        "decline" => "declined",
        _ => {
            return Err(AppError::validation(
                serde_json::json!({"action": "Выберите accept или decline"}),
            ));
        }
    };
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    let conversation_id: Uuid = sqlx::query_scalar(
        "SELECT conversation_id FROM conversation_invitations WHERE id = $1 AND invitee_id = $2 AND status = 'pending' FOR UPDATE",
    )
    .bind(invitation_id)
    .bind(viewer_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(AppError::internal)?
    .ok_or_else(|| AppError::not_found("INVITATION_NOT_FOUND", "Приглашение не найдено"))?;
    if status == "accepted" {
        add_member(&mut tx, conversation_id, viewer_id).await?;
    }
    sqlx::query(
        "UPDATE conversation_invitations SET status = $2, updated_at = NOW() WHERE id = $1",
    )
    .bind(invitation_id)
    .bind(status)
    .execute(&mut *tx)
    .await
    .map_err(AppError::internal)?;
    tx.commit().await.map_err(AppError::internal)?;
    let invitation = conversation_invitation_by_id(&state, viewer_id, invitation_id).await?;
    Ok(Json(ApiResponse::new(invitation)))
}

pub async fn messages(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(conversation_id): Path<Uuid>,
) -> Result<Json<ApiResponse<Vec<ChatMessageResponse>>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_member(&state, conversation_id, viewer_id).await?;
    let rows: Vec<ChatMessageResponse> = sqlx::query_as(
        r#"SELECT message.id, message.conversation_id, message.sender_id, sender.display_name AS sender_name,
                  message.kind, message.body, message.proposal_detail,
                  (SELECT COUNT(*) FROM chat_message_votes vote WHERE vote.message_id = message.id) AS vote_count,
                  EXISTS(SELECT 1 FROM chat_message_votes vote WHERE vote.message_id = message.id AND vote.user_id = $2) AS is_voted,
                  (message.sender_id = $2) AS is_mine,
                  (message.sender_id = $2
                   AND EXISTS(SELECT 1 FROM conversation_members reader WHERE reader.conversation_id = message.conversation_id AND reader.user_id <> message.sender_id)
                   AND NOT EXISTS(SELECT 1 FROM conversation_members reader WHERE reader.conversation_id = message.conversation_id AND reader.user_id <> message.sender_id AND COALESCE(reader.last_read_at, reader.joined_at) < message.created_at)) AS is_read,
                  reply.id AS reply_to_id, reply_sender.display_name AS reply_to_sender_name,
                  reply.body AS reply_to_body, reply.kind AS reply_to_kind,
                  message.attachment_name, message.attachment_content_type, message.attachment_bytes,
                  message.duration_seconds,
                  CASE WHEN message.attachment_object_key IS NULL THEN NULL ELSE 'social/conversations/' || message.conversation_id || '/messages/' || message.id || '/content' END AS content_path,
                  message.edited_at, message.created_at
           FROM chat_messages message
           JOIN users sender ON sender.id = message.sender_id
           LEFT JOIN chat_messages reply ON reply.id = message.reply_to_id
           LEFT JOIN users reply_sender ON reply_sender.id = reply.sender_id
           WHERE message.conversation_id = $1 ORDER BY message.created_at LIMIT 300"#,
    )
    .bind(conversation_id)
    .bind(viewer_id)
    .fetch_all(&state.db)
    .await
    .map_err(AppError::internal)?;
    mark_conversation_read(&state, viewer_id, conversation_id).await?;
    Ok(Json(ApiResponse::new(rows)))
}

pub async fn message(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path((conversation_id, message_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<ApiResponse<ChatMessageResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_member(&state, conversation_id, viewer_id).await?;
    let message = message_by_id(&state, viewer_id, message_id).await?;
    if message.conversation_id != conversation_id {
        return Err(AppError {
            status: StatusCode::NOT_FOUND,
            code: "MESSAGE_NOT_FOUND",
            message: "Сообщение не найдено".into(),
            fields: None,
        });
    }
    mark_conversation_read(&state, viewer_id, conversation_id).await?;
    Ok(Json(ApiResponse::new(message)))
}

async fn mark_conversation_read(
    state: &AppState,
    viewer_id: Uuid,
    conversation_id: Uuid,
) -> Result<(), AppError> {
    sqlx::query("UPDATE conversation_members SET last_read_at = NOW() WHERE conversation_id = $1 AND user_id = $2")
        .bind(conversation_id)
        .bind(viewer_id)
        .execute(&state.db)
        .await
        .map_err(AppError::internal)?;
    notifications::mark_entity_read(state, viewer_id, "conversation", conversation_id).await?;
    let _ = state.chat_events.send(ChatRealtimeEvent {
        event: "read".into(),
        conversation_id,
        message_id: None,
        user_id: Some(viewer_id),
    });
    Ok(())
}

pub async fn send_message(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(conversation_id): Path<Uuid>,
    Json(request): Json<SendMessageRequest>,
) -> Result<(StatusCode, Json<ApiResponse<ChatMessageResponse>>), AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_member(&state, conversation_id, viewer_id).await?;
    let body = request.body.trim();
    if body.is_empty()
        || body.chars().count() > 2_000
        || !matches!(
            request.kind.as_str(),
            "text" | "placeProposal" | "timeProposal"
        )
    {
        return Err(AppError::validation(
            serde_json::json!({"message": "Сообщение должно содержать от 1 до 2000 символов"}),
        ));
    }
    ensure_reply_target(&state, conversation_id, request.reply_to_id).await?;
    let id = Uuid::new_v4();
    sqlx::query("INSERT INTO chat_messages (id, conversation_id, sender_id, kind, body, proposal_detail, reply_to_id) VALUES ($1,$2,$3,$4,$5,$6,$7)")
        .bind(id)
        .bind(conversation_id)
        .bind(viewer_id)
        .bind(request.kind)
        .bind(body)
        .bind(clean(request.proposal_detail))
        .bind(request.reply_to_id)
        .execute(&state.db)
        .await
        .map_err(AppError::internal)?;
    sqlx::query("UPDATE conversations SET updated_at = NOW() WHERE id = $1")
        .bind(conversation_id)
        .execute(&state.db)
        .await
        .map_err(AppError::internal)?;
    let message = message_by_id(&state, viewer_id, id).await?;
    broadcast_message(&state, conversation_id, id, "message");
    notify_conversation_members(&state, &message).await?;
    Ok((StatusCode::CREATED, Json(ApiResponse::new(message))))
}

pub async fn edit_message(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path((conversation_id, message_id)): Path<(Uuid, Uuid)>,
    Json(request): Json<EditMessageRequest>,
) -> Result<Json<ApiResponse<ChatMessageResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_member(&state, conversation_id, viewer_id).await?;
    let body = request.body.trim();
    if body.is_empty() || body.chars().count() > 2_000 {
        return Err(AppError::validation(
            serde_json::json!({"message": "Сообщение должно содержать от 1 до 2000 символов"}),
        ));
    }
    let updated = sqlx::query_scalar::<_, Uuid>(
        "UPDATE chat_messages SET body = $1, edited_at = NOW() WHERE id = $2 AND conversation_id = $3 AND sender_id = $4 AND kind = 'text' RETURNING id",
    )
    .bind(body)
    .bind(message_id)
    .bind(conversation_id)
    .bind(viewer_id)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?;
    if updated.is_none() {
        return Err(AppError {
            status: StatusCode::NOT_FOUND,
            code: "MESSAGE_NOT_EDITABLE",
            message: "Сообщение не найдено или его нельзя редактировать".into(),
            fields: None,
        });
    }
    let message = message_by_id(&state, viewer_id, message_id).await?;
    broadcast_message(&state, conversation_id, message_id, "messageUpdated");
    Ok(Json(ApiResponse::new(message)))
}

pub async fn delete_message(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path((conversation_id, message_id)): Path<(Uuid, Uuid)>,
) -> Result<StatusCode, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_member(&state, conversation_id, viewer_id).await?;
    let row: Option<(Option<String>,)> = sqlx::query_as(
        "SELECT attachment_object_key FROM chat_messages WHERE id = $1 AND conversation_id = $2 AND sender_id = $3 AND kind NOT IN ('system', 'invitation')",
    )
    .bind(message_id)
    .bind(conversation_id)
    .bind(viewer_id)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?;
    let Some((object_key,)) = row else {
        return Err(AppError {
            status: StatusCode::NOT_FOUND,
            code: "MESSAGE_NOT_DELETABLE",
            message: "Сообщение не найдено или его нельзя удалить".into(),
            fields: None,
        });
    };
    sqlx::query("DELETE FROM chat_messages WHERE id = $1")
        .bind(message_id)
        .execute(&state.db)
        .await
        .map_err(AppError::internal)?;
    if let Some(object_key) = object_key {
        cache::delete(&state, &chat_attachment_cache_key(&object_key)).await;
        if let Some(storage) = state.object_storage.clone()
            && let Err(error) = storage.delete(&object_key).await
        {
            warn!(error = %error, %object_key, "failed to remove deleted chat object");
        }
    }
    broadcast_message(&state, conversation_id, message_id, "messageDeleted");
    Ok(StatusCode::NO_CONTENT)
}

pub async fn vote_message(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path((conversation_id, message_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<ApiResponse<ChatMessageResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_member(&state, conversation_id, viewer_id).await?;
    let proposal: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM chat_messages WHERE id = $1 AND conversation_id = $2 AND kind IN ('placeProposal', 'timeProposal'))",
    )
    .bind(message_id)
    .bind(conversation_id)
    .fetch_one(&state.db)
    .await
    .map_err(AppError::internal)?;
    if !proposal {
        return Err(AppError {
            status: StatusCode::NOT_FOUND,
            code: "PROPOSAL_NOT_FOUND",
            message: "Предложение не найдено".into(),
            fields: None,
        });
    }
    sqlx::query("INSERT INTO chat_message_votes (message_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING")
        .bind(message_id)
        .bind(viewer_id)
        .execute(&state.db)
        .await
        .map_err(AppError::internal)?;
    let message = message_by_id(&state, viewer_id, message_id).await?;
    broadcast_message(&state, conversation_id, message_id, "messageUpdated");
    Ok(Json(ApiResponse::new(message)))
}

async fn conversation_by_id(
    state: &AppState,
    viewer_id: Uuid,
    conversation_id: Uuid,
) -> Result<ConversationResponse, AppError> {
    let row: Option<ConversationResponse> = sqlx::query_as(
        r#"SELECT conversation.id, conversation.kind, COALESCE(conversation.title, other.display_name, 'Чат') AS title,
                  other.id AS participant_id,
                  CASE
                      WHEN conversation.avatar_object_key IS NOT NULL THEN 'social/conversations/' || conversation.id || '/avatar'
                      WHEN activity_avatar.id IS NOT NULL THEN 'activities/' || conversation.activity_id || '/photos/' || activity_avatar.id || '/content'
                      WHEN avatar.id IS NOT NULL THEN 'users/photos/' || avatar.id || '/content'
                      ELSE NULL
                  END AS avatar_path,
                  conversation.activity_id, conversation.created_by AS created_by_id,
                  last_message.body AS last_message, last_message.created_at AS last_message_at,
                  0::bigint AS unread_count,
                  (SELECT COUNT(*) FROM conversation_members participant WHERE participant.conversation_id = conversation.id) AS member_count,
                  (member.archived_at IS NOT NULL) AS is_archived,
                  COALESCE(other.last_seen_at > NOW() - INTERVAL '2 minutes', FALSE) AS is_online,
                  other.last_seen_at
           FROM conversations conversation
           JOIN conversation_members member ON member.conversation_id = conversation.id AND member.user_id = $1
           LEFT JOIN LATERAL (SELECT users.id, users.display_name, users.last_seen_at FROM conversation_members others JOIN users ON users.id = others.user_id WHERE others.conversation_id = conversation.id AND others.user_id <> $1 LIMIT 1) other ON TRUE
           LEFT JOIN LATERAL (SELECT id FROM user_photos WHERE user_id = other.id AND is_current_avatar = TRUE LIMIT 1) avatar ON TRUE
           LEFT JOIN LATERAL (SELECT id FROM activity_photos WHERE activity_id = conversation.activity_id ORDER BY is_cover DESC, sort_index LIMIT 1) activity_avatar ON TRUE
           LEFT JOIN LATERAL (SELECT body, created_at FROM chat_messages WHERE conversation_id = conversation.id ORDER BY created_at DESC LIMIT 1) last_message ON TRUE
           WHERE conversation.id = $2"#,
    )
    .bind(viewer_id)
    .bind(conversation_id)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?;
    row.ok_or_else(|| AppError {
        status: StatusCode::NOT_FOUND,
        code: "CONVERSATION_NOT_FOUND",
        message: "Чат не найден".into(),
        fields: None,
    })
}

async fn message_by_id(
    state: &AppState,
    viewer_id: Uuid,
    message_id: Uuid,
) -> Result<ChatMessageResponse, AppError> {
    sqlx::query_as(
        r#"SELECT message.id, message.conversation_id, message.sender_id, sender.display_name AS sender_name,
                  message.kind, message.body, message.proposal_detail,
                  (SELECT COUNT(*) FROM chat_message_votes vote WHERE vote.message_id = message.id) AS vote_count,
                  EXISTS(SELECT 1 FROM chat_message_votes vote WHERE vote.message_id = message.id AND vote.user_id = $2) AS is_voted,
                  (message.sender_id = $2) AS is_mine,
                  (message.sender_id = $2
                   AND EXISTS(SELECT 1 FROM conversation_members reader WHERE reader.conversation_id = message.conversation_id AND reader.user_id <> message.sender_id)
                   AND NOT EXISTS(SELECT 1 FROM conversation_members reader WHERE reader.conversation_id = message.conversation_id AND reader.user_id <> message.sender_id AND COALESCE(reader.last_read_at, reader.joined_at) < message.created_at)) AS is_read,
                  reply.id AS reply_to_id, reply_sender.display_name AS reply_to_sender_name,
                  reply.body AS reply_to_body, reply.kind AS reply_to_kind,
                  message.attachment_name, message.attachment_content_type, message.attachment_bytes,
                  message.duration_seconds,
                  CASE WHEN message.attachment_object_key IS NULL THEN NULL ELSE 'social/conversations/' || message.conversation_id || '/messages/' || message.id || '/content' END AS content_path,
                  message.edited_at, message.created_at
           FROM chat_messages message
           JOIN users sender ON sender.id = message.sender_id
           LEFT JOIN chat_messages reply ON reply.id = message.reply_to_id
           LEFT JOIN users reply_sender ON reply_sender.id = reply.sender_id
           WHERE message.id = $1"#,
    )
    .bind(message_id)
    .bind(viewer_id)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?
    .ok_or_else(|| AppError {
        status: StatusCode::NOT_FOUND,
        code: "MESSAGE_NOT_FOUND",
        message: "Сообщение не найдено".into(),
        fields: None,
    })
}

pub async fn upload_attachment(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(conversation_id): Path<Uuid>,
    Query(query): Query<AttachmentUploadQuery>,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<ApiResponse<ChatMessageResponse>>), AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_member(&state, conversation_id, viewer_id).await?;
    if !matches!(
        query.kind.as_str(),
        "image" | "video" | "file" | "audio" | "voice"
    ) {
        return Err(AppError::validation(serde_json::json!({
            "kind": "Неизвестный тип вложения"
        })));
    }
    let field = multipart
        .next_field()
        .await
        .map_err(|_| {
            AppError::validation(serde_json::json!({"file": "Не удалось прочитать файл"}))
        })?
        .ok_or_else(|| AppError::validation(serde_json::json!({"file": "Выберите файл"})))?;
    if field.name() != Some("file") {
        return Err(AppError::validation(
            serde_json::json!({"file": "Ожидается поле file"}),
        ));
    }
    let file_name = safe_file_name(field.file_name().unwrap_or("attachment"));
    let content_type = field
        .content_type()
        .unwrap_or("application/octet-stream")
        .to_owned();
    if !attachment_content_type_is_valid(&query.kind, &content_type) {
        return Err(AppError::validation(serde_json::json!({
            "file": "Формат файла не соответствует выбранному типу"
        })));
    }
    let data = field
        .bytes()
        .await
        .map_err(|_| {
            AppError::validation(serde_json::json!({"file": "Не удалось прочитать файл"}))
        })?
        .to_vec();
    let limit = attachment_limit(&query.kind);
    if data.is_empty() || data.len() > limit {
        return Err(AppError::validation(serde_json::json!({
            "file": format!("Размер вложения должен быть от 1 байта до {} МБ", limit / 1024 / 1024)
        })));
    }
    if query
        .duration_seconds
        .is_some_and(|value| !value.is_finite() || !(0.0..=21_600.0).contains(&value))
    {
        return Err(AppError::validation(serde_json::json!({
            "durationSeconds": "Некорректная длительность медиа"
        })));
    }
    ensure_reply_target(&state, conversation_id, query.reply_to_id).await?;
    let storage = state.object_storage.clone().ok_or_else(|| AppError {
        status: StatusCode::SERVICE_UNAVAILABLE,
        code: "OBJECT_STORAGE_UNAVAILABLE",
        message: "Хранилище вложений пока не настроено".into(),
        fields: None,
    })?;
    let message_id = Uuid::new_v4();
    let extension = safe_extension(&file_name, &content_type);
    let object_key = storage.chat_object_key(conversation_id, message_id, &extension);
    let bytes = i32::try_from(data.len()).map_err(AppError::internal)?;
    let cacheable_data =
        (data.len() <= state.config.redis_media_cache_max_bytes).then(|| data.clone());
    storage
        .put_image(&object_key, &content_type, data)
        .await
        .map_err(|error| {
            warn!(error = %error, %conversation_id, "chat attachment upload failed");
            AppError::service_unavailable()
        })?;
    let body = attachment_title(&query.kind, &file_name);
    let insert = sqlx::query(
        "INSERT INTO chat_messages (id, conversation_id, sender_id, kind, body, attachment_object_key, attachment_name, attachment_content_type, attachment_bytes, duration_seconds, reply_to_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)",
    )
    .bind(message_id)
    .bind(conversation_id)
    .bind(viewer_id)
    .bind(&query.kind)
    .bind(body)
    .bind(&object_key)
    .bind(&file_name)
    .bind(&content_type)
    .bind(bytes)
    .bind(query.duration_seconds)
    .bind(query.reply_to_id)
    .execute(&state.db)
    .await;
    if let Err(error) = insert {
        if let Err(cleanup_error) = storage.delete(&object_key).await {
            warn!(error = %cleanup_error, %object_key, "failed to remove unattached chat object");
        }
        return Err(AppError::internal(error));
    }
    if let Some(data) = cacheable_data {
        cache::set_bytes(
            &state,
            &chat_attachment_cache_key(&object_key),
            &data,
            state.config.redis_media_cache_ttl_seconds,
        )
        .await;
    }
    sqlx::query("UPDATE conversations SET updated_at = NOW() WHERE id = $1")
        .bind(conversation_id)
        .execute(&state.db)
        .await
        .map_err(AppError::internal)?;
    let message = message_by_id(&state, viewer_id, message_id).await?;
    broadcast_message(&state, conversation_id, message_id, "message");
    notify_conversation_members(&state, &message).await?;
    Ok((StatusCode::CREATED, Json(ApiResponse::new(message))))
}

pub async fn download_attachment(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path((conversation_id, message_id)): Path<(Uuid, Uuid)>,
) -> Result<Response, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_member(&state, conversation_id, viewer_id).await?;
    let attachment: Option<(String, String, String)> = sqlx::query_as(
        "SELECT attachment_object_key, attachment_content_type, attachment_name FROM chat_messages WHERE id = $1 AND conversation_id = $2 AND attachment_object_key IS NOT NULL",
    )
    .bind(message_id)
    .bind(conversation_id)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?;
    let (object_key, stored_content_type, file_name) = attachment.ok_or_else(|| AppError {
        status: StatusCode::NOT_FOUND,
        code: "ATTACHMENT_NOT_FOUND",
        message: "Вложение не найдено".into(),
        fields: None,
    })?;
    let etag = format!("\"chat-attachment-{message_id}\"");
    let etag_header = HeaderValue::from_str(&etag).map_err(AppError::internal)?;
    let is_not_modified = headers
        .get(header::IF_NONE_MATCH)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| etag_value_matches(value, &etag));
    if is_not_modified {
        let mut response = Response::new(Body::empty());
        *response.status_mut() = StatusCode::NOT_MODIFIED;
        response.headers_mut().insert(header::ETAG, etag_header);
        response.headers_mut().insert(
            header::CACHE_CONTROL,
            HeaderValue::from_static(CHAT_ATTACHMENT_CACHE_CONTROL),
        );
        return Ok(response);
    }

    let cache_key = chat_attachment_cache_key(&object_key);
    let (content_type, data) = if let Some(data) = cache::get_bytes(&state, &cache_key).await {
        (stored_content_type.clone(), data)
    } else {
        let storage = state.object_storage.clone().ok_or_else(|| AppError {
            status: StatusCode::SERVICE_UNAVAILABLE,
            code: "OBJECT_STORAGE_UNAVAILABLE",
            message: "Хранилище вложений пока не настроено".into(),
            fields: None,
        })?;
        let (content_type, data) = storage.get_image(&object_key).await.map_err(|error| {
            warn!(error = %error, %message_id, "chat attachment download failed");
            AppError::service_unavailable()
        })?;
        if data.len() <= state.config.redis_media_cache_max_bytes {
            cache::set_bytes(
                &state,
                &cache_key,
                &data,
                state.config.redis_media_cache_ttl_seconds,
            )
            .await;
        }
        (content_type, data)
    };
    let content_type = HeaderValue::from_str(if content_type.is_empty() {
        &stored_content_type
    } else {
        &content_type
    })
    .map_err(AppError::internal)?;
    let disposition = HeaderValue::from_str(&format!(
        "inline; filename=\"{}\"",
        safe_file_name(&file_name)
    ))
    .map_err(AppError::internal)?;
    Ok((
        [
            (header::CONTENT_TYPE, content_type),
            (header::CONTENT_DISPOSITION, disposition),
            (
                header::CACHE_CONTROL,
                HeaderValue::from_static(CHAT_ATTACHMENT_CACHE_CONTROL),
            ),
            (header::ETAG, etag_header),
            (
                header::X_CONTENT_TYPE_OPTIONS,
                HeaderValue::from_static("nosniff"),
            ),
        ],
        Body::from(data),
    )
        .into_response())
}

pub async fn upload_conversation_avatar(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(conversation_id): Path<Uuid>,
    mut multipart: Multipart,
) -> Result<Json<ApiResponse<ConversationResponse>>, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_conversation_creator(&state, conversation_id, viewer_id).await?;
    let field = multipart
        .next_field()
        .await
        .map_err(|_| {
            AppError::validation(serde_json::json!({"file": "Не удалось прочитать фото"}))
        })?
        .ok_or_else(|| AppError::validation(serde_json::json!({"file": "Выберите фото"})))?;
    if field.name() != Some("file") {
        return Err(AppError::validation(
            serde_json::json!({"file": "Ожидается поле file"}),
        ));
    }
    let file_name = safe_file_name(field.file_name().unwrap_or("group.jpg"));
    let content_type = field.content_type().unwrap_or("image/jpeg").to_owned();
    if !attachment_content_type_is_valid("image", &content_type) {
        return Err(AppError::validation(
            serde_json::json!({"file": "Поддерживаются JPEG, PNG, WebP и HEIC"}),
        ));
    }
    let data = field
        .bytes()
        .await
        .map_err(|_| {
            AppError::validation(serde_json::json!({"file": "Не удалось прочитать фото"}))
        })?
        .to_vec();
    if data.is_empty() || data.len() > MAX_CHAT_AVATAR_BYTES {
        return Err(AppError::validation(
            serde_json::json!({"file": "Фото должно быть не больше 5 МБ"}),
        ));
    }
    let storage = state.object_storage.clone().ok_or_else(|| AppError {
        status: StatusCode::SERVICE_UNAVAILABLE,
        code: "OBJECT_STORAGE_UNAVAILABLE",
        message: "Хранилище изображений пока не настроено".into(),
        fields: None,
    })?;
    let old_key: Option<String> =
        sqlx::query_scalar("SELECT avatar_object_key FROM conversations WHERE id = $1")
            .bind(conversation_id)
            .fetch_one(&state.db)
            .await
            .map_err(AppError::internal)?;
    let extension = safe_extension(&file_name, &content_type);
    let object_key = storage.chat_object_key(conversation_id, Uuid::new_v4(), &extension);
    let bytes = i32::try_from(data.len()).map_err(AppError::internal)?;
    storage
        .put_image(&object_key, &content_type, data)
        .await
        .map_err(|error| {
            warn!(error = %error, %conversation_id, "group avatar upload failed");
            AppError::service_unavailable()
        })?;
    sqlx::query(
        "UPDATE conversations SET avatar_object_key = $2, avatar_content_type = $3, avatar_bytes = $4, updated_at = NOW() WHERE id = $1",
    )
    .bind(conversation_id)
    .bind(&object_key)
    .bind(&content_type)
    .bind(bytes)
    .execute(&state.db)
    .await
    .map_err(AppError::internal)?;
    if let Some(old_key) = old_key {
        cache::delete(&state, &chat_attachment_cache_key(&old_key)).await;
        let _ = storage.delete(&old_key).await;
    }
    Ok(Json(ApiResponse::new(
        conversation_by_id(&state, viewer_id, conversation_id).await?,
    )))
}

pub async fn download_conversation_avatar(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(conversation_id): Path<Uuid>,
) -> Result<Response, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_member(&state, conversation_id, viewer_id).await?;
    let (object_key, stored_content_type): (String, String) = sqlx::query_as(
        "SELECT avatar_object_key, avatar_content_type FROM conversations WHERE id = $1 AND avatar_object_key IS NOT NULL",
    )
    .bind(conversation_id)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?
    .ok_or_else(|| AppError::not_found("CHAT_AVATAR_NOT_FOUND", "Фото чата не найдено"))?;
    let storage = state
        .object_storage
        .clone()
        .ok_or_else(AppError::service_unavailable)?;
    let cache_key = chat_attachment_cache_key(&object_key);
    let (content_type, data) = if let Some(data) = cache::get_bytes(&state, &cache_key).await {
        (stored_content_type.clone(), data)
    } else {
        let result = storage
            .get_image(&object_key)
            .await
            .map_err(|_| AppError::service_unavailable())?;
        if result.1.len() <= state.config.redis_media_cache_max_bytes {
            cache::set_bytes(
                &state,
                &cache_key,
                &result.1,
                state.config.redis_media_cache_ttl_seconds,
            )
            .await;
        }
        result
    };
    let content_type = HeaderValue::from_str(if content_type.is_empty() {
        &stored_content_type
    } else {
        &content_type
    })
    .map_err(AppError::internal)?;
    Ok((
        [
            (header::CONTENT_TYPE, content_type),
            (
                header::CACHE_CONTROL,
                HeaderValue::from_static("private, max-age=300"),
            ),
            (
                header::X_CONTENT_TYPE_OPTIONS,
                HeaderValue::from_static("nosniff"),
            ),
        ],
        Body::from(data),
    )
        .into_response())
}

pub async fn live(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(conversation_id): Path<Uuid>,
) -> Result<Response, AppError> {
    let viewer_id = active_user_id(&headers, &state).await?;
    ensure_member(&state, conversation_id, viewer_id).await?;
    Ok(ws
        .on_upgrade(move |socket| chat_socket(socket, state, conversation_id, viewer_id))
        .into_response())
}

async fn chat_socket(
    mut socket: WebSocket,
    state: AppState,
    conversation_id: Uuid,
    viewer_id: Uuid,
) {
    let mut events = state.chat_events.subscribe();
    loop {
        tokio::select! {
            incoming = socket.next() => {
                let Some(Ok(message)) = incoming else { break };
                match message {
                    Message::Text(text)
                        if serde_json::from_str::<ChatSocketCommand>(&text)
                            .is_ok_and(|command| command.event == "typing") =>
                    {
                        let _ = state.chat_events.send(ChatRealtimeEvent {
                            event: "typing".into(),
                            conversation_id,
                            message_id: None,
                            user_id: Some(viewer_id),
                        });
                    }
                    Message::Close(_) => break,
                    Message::Ping(data) if socket.send(Message::Pong(data.clone())).await.is_err() => break,
                    _ => {}
                }
            }
            event = events.recv() => {
                match event {
                    Ok(event) if event.conversation_id == conversation_id => {
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

fn broadcast_message(state: &AppState, conversation_id: Uuid, message_id: Uuid, event: &str) {
    let _ = state.chat_events.send(ChatRealtimeEvent {
        event: event.into(),
        conversation_id,
        message_id: Some(message_id),
        user_id: None,
    });
}

async fn notify_conversation_members(
    state: &AppState,
    message: &ChatMessageResponse,
) -> Result<(), AppError> {
    let recipients: Vec<Uuid> = sqlx::query_scalar(
        "SELECT user_id FROM conversation_members WHERE conversation_id = $1 AND user_id <> $2",
    )
    .bind(message.conversation_id)
    .bind(message.sender_id)
    .fetch_all(&state.db)
    .await
    .map_err(AppError::internal)?;
    let preview = match message.kind.as_str() {
        "image" => "Фотография".into(),
        "video" => "Видео".into(),
        "voice" => "Голосовое сообщение".into(),
        "audio" => "Аудиофайл".into(),
        "file" => format!(
            "Файл: {}",
            message.attachment_name.as_deref().unwrap_or("вложение")
        ),
        "placeProposal" => format!("Предлагает место: {}", message.body),
        "timeProposal" => format!("Предлагает время: {}", message.body),
        _ => message.body.chars().take(180).collect(),
    };
    for recipient_id in recipients {
        notifications::emit(
            state,
            NotificationDraft {
                recipient_id,
                actor_id: Some(message.sender_id),
                category: "messages",
                kind: "new_message",
                title: message.sender_name.clone(),
                body: preview.clone(),
                entity_type: Some("conversation"),
                entity_id: Some(message.conversation_id),
                action_path: Some(format!("gonow://chats/{}", message.conversation_id)),
                payload: serde_json::json!({"messageId": message.id}),
                dedupe_key: Some(format!("message:{}:{recipient_id}", message.id)),
            },
        )
        .await?;
    }
    Ok(())
}

async fn user_display_name(state: &AppState, user_id: Uuid) -> Result<String, AppError> {
    sqlx::query_scalar("SELECT display_name FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(&state.db)
        .await
        .map_err(AppError::internal)
}

fn attachment_limit(kind: &str) -> usize {
    match kind {
        "image" => 15 * 1024 * 1024,
        "audio" | "voice" => 25 * 1024 * 1024,
        _ => MAX_CHAT_ATTACHMENT_BYTES,
    }
}

fn chat_attachment_cache_key(object_key: &str) -> String {
    format!("cache:chat-attachment:v1:{object_key}")
}

fn etag_value_matches(value: &str, etag: &str) -> bool {
    value
        .split(',')
        .any(|candidate| matches!(candidate.trim(), "*") || candidate.trim() == etag)
}

fn attachment_content_type_is_valid(kind: &str, content_type: &str) -> bool {
    match kind {
        "image" => content_type.starts_with("image/"),
        "video" => content_type.starts_with("video/"),
        "audio" | "voice" => content_type.starts_with("audio/"),
        "file" => {
            !content_type.starts_with("text/html") && content_type != "application/x-mach-binary"
        }
        _ => false,
    }
}

fn safe_file_name(value: &str) -> String {
    let name = value
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or("attachment")
        .chars()
        .filter(|character| !character.is_control() && *character != '"')
        .take(160)
        .collect::<String>();
    if name.trim().is_empty() {
        "attachment".into()
    } else {
        name
    }
}

fn safe_extension(file_name: &str, content_type: &str) -> String {
    let from_name = file_name
        .rsplit_once('.')
        .map(|(_, extension)| extension.to_ascii_lowercase())
        .filter(|extension| {
            !extension.is_empty()
                && extension.len() <= 10
                && extension.chars().all(|value| value.is_ascii_alphanumeric())
        });
    from_name.unwrap_or_else(|| match content_type {
        "image/jpeg" => "jpg".into(),
        "image/png" => "png".into(),
        "image/webp" => "webp".into(),
        "video/mp4" => "mp4".into(),
        "audio/mp4" => "m4a".into(),
        "audio/mpeg" => "mp3".into(),
        _ => "bin".into(),
    })
}

fn attachment_title(kind: &str, file_name: &str) -> String {
    match kind {
        "image" => "Фотография".into(),
        "video" => "Видео".into(),
        "audio" => format!("Аудио · {file_name}"),
        "voice" => "Голосовое сообщение".into(),
        _ => file_name.into(),
    }
}

async fn ensure_reply_target(
    state: &AppState,
    conversation_id: Uuid,
    reply_to_id: Option<Uuid>,
) -> Result<(), AppError> {
    let Some(reply_to_id) = reply_to_id else {
        return Ok(());
    };
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM chat_messages WHERE id = $1 AND conversation_id = $2)",
    )
    .bind(reply_to_id)
    .bind(conversation_id)
    .fetch_one(&state.db)
    .await
    .map_err(AppError::internal)?;
    if exists {
        Ok(())
    } else {
        Err(AppError::validation(
            serde_json::json!({"replyToId": "Сообщение для ответа не найдено"}),
        ))
    }
}

async fn ensure_conversation_creator(
    state: &AppState,
    conversation_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let allowed: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM conversations WHERE id = $1 AND created_by = $2 AND kind IN ('group', 'activity'))",
    )
    .bind(conversation_id)
    .bind(user_id)
    .fetch_one(&state.db)
    .await
    .map_err(AppError::internal)?;
    if allowed {
        Ok(())
    } else {
        Err(AppError::forbidden(
            "CHAT_CREATOR_REQUIRED",
            "Действие доступно только создателю чата",
        ))
    }
}

async fn add_friend_or_invite(
    tx: &mut Transaction<'_, Postgres>,
    conversation_id: Uuid,
    inviter_id: Uuid,
    user_id: Uuid,
) -> Result<bool, AppError> {
    let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)")
        .bind(user_id)
        .fetch_one(&mut **tx)
        .await
        .map_err(AppError::internal)?;
    if !exists {
        return Err(AppError::not_found(
            "USER_NOT_FOUND",
            "Пользователь не найден",
        ));
    }
    if user_id == inviter_id {
        add_member(tx, conversation_id, user_id).await?;
        return Ok(true);
    }
    let is_friend: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM friendships WHERE status = 'accepted' AND ((user_low = $1 AND user_high = $2) OR (user_low = $2 AND user_high = $1)))",
    )
    .bind(inviter_id)
    .bind(user_id)
    .fetch_one(&mut **tx)
    .await
    .map_err(AppError::internal)?;
    if is_friend {
        add_member(tx, conversation_id, user_id).await?;
        sqlx::query(
            "UPDATE conversation_invitations SET status = 'accepted', updated_at = NOW() WHERE conversation_id = $1 AND invitee_id = $2 AND status = 'pending'",
        )
        .bind(conversation_id)
        .bind(user_id)
        .execute(&mut **tx)
        .await
        .map_err(AppError::internal)?;
        Ok(true)
    } else {
        sqlx::query(
            "INSERT INTO conversation_invitations (id, conversation_id, inviter_id, invitee_id) VALUES ($1,$2,$3,$4) ON CONFLICT (conversation_id, invitee_id) WHERE status = 'pending' DO UPDATE SET inviter_id = EXCLUDED.inviter_id, updated_at = NOW()",
        )
        .bind(Uuid::new_v4())
        .bind(conversation_id)
        .bind(inviter_id)
        .bind(user_id)
        .execute(&mut **tx)
        .await
        .map_err(AppError::internal)?;
        Ok(false)
    }
}

async fn conversation_invitation_by_id(
    state: &AppState,
    viewer_id: Uuid,
    invitation_id: Uuid,
) -> Result<ConversationInvitationResponse, AppError> {
    sqlx::query_as(
        r#"SELECT invitation.id, invitation.conversation_id,
                  COALESCE(conversation.title, 'Групповой чат') AS conversation_title,
                  invitation.inviter_id, inviter.display_name AS inviter_name,
                  invitation.status, invitation.created_at
           FROM conversation_invitations invitation
           JOIN conversations conversation ON conversation.id = invitation.conversation_id
           JOIN users inviter ON inviter.id = invitation.inviter_id
           WHERE invitation.id = $1 AND invitation.invitee_id = $2"#,
    )
    .bind(invitation_id)
    .bind(viewer_id)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?
    .ok_or_else(|| AppError::not_found("INVITATION_NOT_FOUND", "Приглашение не найдено"))
}

async fn ensure_member(
    state: &AppState,
    conversation_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let member: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2)",
    )
    .bind(conversation_id)
    .bind(user_id)
    .fetch_one(&state.db)
    .await
    .map_err(AppError::internal)?;
    if member {
        Ok(())
    } else {
        Err(AppError {
            status: StatusCode::FORBIDDEN,
            code: "CONVERSATION_FORBIDDEN",
            message: "Этот чат недоступен".into(),
            fields: None,
        })
    }
}

async fn add_member(
    tx: &mut Transaction<'_, Postgres>,
    conversation_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    sqlx::query("INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING")
        .bind(conversation_id)
        .bind(user_id)
        .execute(&mut **tx)
        .await
        .map_err(AppError::internal)?;
    Ok(())
}

fn ordered_pair(first: Uuid, second: Uuid) -> (Uuid, Uuid) {
    if first.as_bytes() <= second.as_bytes() {
        (first, second)
    } else {
        (second, first)
    }
}

fn ordered_pair_key(first: Uuid, second: Uuid) -> String {
    let (low, high) = ordered_pair(first, second);
    format!("{low}:{high}")
}

fn clean(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

fn invitation_chat_body(
    sender_name: &str,
    template: &str,
    proposed_at: Option<DateTime<Utc>>,
    place: Option<&str>,
    message: Option<&str>,
) -> String {
    let mut lines = vec![format!(
        "{sender_name} приглашает: {}",
        template_title(template)
    )];
    if let Some(proposed_at) = proposed_at {
        lines.push(format!(
            "Когда: {}",
            proposed_at.format("%d.%m.%Y %H:%M UTC")
        ));
    }
    if let Some(place) = place {
        lines.push(format!("Где: {place}"));
    }
    if let Some(message) = message {
        lines.push(message.to_owned());
    }
    lines.join("\n")
}

fn template_title(value: &str) -> &'static str {
    match value {
        "walk" => "Прогулка",
        "coffee" => "Кофе",
        "cinema" => "Кино",
        "dinner" => "Ужин",
        "bicycle" => "Велопрогулка",
        "games" => "Игры",
        "concert" => "Концерт",
        "talk" => "Поговорить",
        _ => "Активность",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn direct_conversation_key_is_order_independent() {
        let first = Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap();
        let second = Uuid::parse_str("00000000-0000-0000-0000-000000000002").unwrap();
        assert_eq!(
            ordered_pair_key(first, second),
            ordered_pair_key(second, first)
        );
    }

    #[test]
    fn invitation_templates_have_readable_titles() {
        assert_eq!(template_title("coffee"), "Кофе");
        assert_eq!(template_title("unknown"), "Активность");
    }

    #[test]
    fn chat_attachments_validate_their_declared_media_type() {
        assert!(attachment_content_type_is_valid("image", "image/jpeg"));
        assert!(attachment_content_type_is_valid("video", "video/quicktime"));
        assert!(attachment_content_type_is_valid("voice", "audio/mp4"));
        assert!(attachment_content_type_is_valid("file", "application/pdf"));
        assert!(!attachment_content_type_is_valid("image", "video/mp4"));
        assert!(!attachment_content_type_is_valid("file", "text/html"));
    }

    #[test]
    fn chat_attachment_names_are_safe_for_storage_and_headers() {
        assert_eq!(safe_file_name("../../private/voice\".m4a"), "voice.m4a");
        assert_eq!(safe_file_name("  "), "attachment");
        assert_eq!(safe_extension("photo.JPEG", "image/jpeg"), "jpeg");
        assert_eq!(safe_extension("photo.bad-extension!", "image/png"), "png");
    }

    #[test]
    fn chat_attachment_cache_keys_are_versioned_and_object_scoped() {
        assert_eq!(
            chat_attachment_cache_key("gonow/chat/one/photo.jpg"),
            "cache:chat-attachment:v1:gonow/chat/one/photo.jpg"
        );
        assert_ne!(
            chat_attachment_cache_key("gonow/chat/one/photo.jpg"),
            chat_attachment_cache_key("gonow/chat/two/photo.jpg")
        );
    }

    #[test]
    fn chat_attachment_etags_support_browser_revalidation() {
        let etag = "\"chat-attachment-123\"";
        assert!(etag_value_matches(etag, etag));
        assert!(etag_value_matches("\"old\", \"chat-attachment-123\"", etag));
        assert!(etag_value_matches("*", etag));
        assert!(!etag_value_matches("\"different\"", etag));
    }
}
