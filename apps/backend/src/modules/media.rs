use axum::{
    Json,
    body::Body,
    extract::{Multipart, Path, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use tracing::warn;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::{
    app::AppState,
    infrastructure::{cache, storage::S3ObjectStorage},
    shared::{errors::AppError, response::ApiResponse},
};

use super::users::active_user_id;

pub const MAX_IMAGE_BYTES: usize = 8 * 1024 * 1024;
const MAX_GALLERY_PHOTOS: i64 = 12;

#[derive(Clone, Debug, Deserialize, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ProfilePhotoResponse {
    pub id: Uuid,
    pub content_type: String,
    pub bytes: i32,
    pub created_at: DateTime<Utc>,
    pub content_path: String,
    pub is_avatar: bool,
    pub is_current_avatar: bool,
    pub description: Option<String>,
    pub like_count: i64,
    pub is_liked: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ProfilePhotosResponse {
    pub avatar: Option<ProfilePhotoResponse>,
    pub avatars: Vec<ProfilePhotoResponse>,
    pub photos: Vec<ProfilePhotoResponse>,
}

#[derive(Debug, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UpdatePhotoRequest {
    pub description: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct PhotoEngagementResponse {
    pub photo_id: Uuid,
    pub like_count: i64,
    pub is_liked: bool,
}

#[derive(FromRow)]
struct ProfilePhotoRow {
    id: Uuid,
    object_key: String,
    content_type: String,
    bytes: i32,
    is_avatar: bool,
    is_current_avatar: bool,
    description: Option<String>,
    like_count: i64,
    is_liked: bool,
    created_at: DateTime<Utc>,
}

impl From<ProfilePhotoRow> for ProfilePhotoResponse {
    fn from(value: ProfilePhotoRow) -> Self {
        Self {
            content_path: format!("users/photos/{}/content", value.id),
            id: value.id,
            content_type: value.content_type,
            bytes: value.bytes,
            created_at: value.created_at,
            is_avatar: value.is_avatar,
            is_current_avatar: value.is_current_avatar,
            description: value.description,
            like_count: value.like_count,
            is_liked: value.is_liked,
        }
    }
}

pub(crate) struct UploadedImage {
    pub content_type: &'static str,
    pub extension: &'static str,
    pub data: Vec<u8>,
}

fn storage(state: &AppState) -> Result<S3ObjectStorage, AppError> {
    state.object_storage.clone().ok_or_else(|| AppError {
        status: StatusCode::SERVICE_UNAVAILABLE,
        code: "OBJECT_STORAGE_UNAVAILABLE",
        message: "Хранилище фотографий пока не настроено".into(),
        fields: None,
    })
}

const MEDIA_CACHE_CONTROL: &str = "private, max-age=604800, immutable";
const MEDIA_CACHE_VERSION: &str = "v1";
const PROFILE_MEDIA_CACHE_VERSION: &str = "v1";

fn media_cache_key(object_key: &str) -> String {
    format!("cache:media:{MEDIA_CACHE_VERSION}:{object_key}")
}

fn profile_media_cache_key(user_id: Uuid) -> String {
    format!("cache:profile-media:{PROFILE_MEDIA_CACHE_VERSION}:{user_id}")
}

async fn invalidate_profile_media(state: &AppState, user_id: Uuid) {
    cache::delete(state, &profile_media_cache_key(user_id)).await;
}

pub(crate) async fn invalidate_cached_image(state: &AppState, object_key: &str) {
    cache::delete(state, &media_cache_key(object_key)).await;
}

pub(crate) async fn cached_image_response(
    state: &AppState,
    request_headers: &HeaderMap,
    object_key: &str,
    database_content_type: &str,
    media_id: Uuid,
) -> Result<Response, AppError> {
    let etag = format!("\"media-{media_id}\"");
    let etag_header = HeaderValue::from_str(&etag).map_err(AppError::internal)?;
    let is_not_modified = request_headers
        .get(header::IF_NONE_MATCH)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| {
            value
                .split(',')
                .any(|candidate| matches!(candidate.trim(), "*") || candidate.trim() == etag)
        });
    if is_not_modified {
        let mut response = Response::new(Body::empty());
        *response.status_mut() = StatusCode::NOT_MODIFIED;
        response.headers_mut().insert(header::ETAG, etag_header);
        response.headers_mut().insert(
            header::CACHE_CONTROL,
            HeaderValue::from_static(MEDIA_CACHE_CONTROL),
        );
        return Ok(response);
    }

    let cache_key = media_cache_key(object_key);
    let (content_type, data) = if let Some(data) = cache::get_bytes(state, &cache_key).await {
        (database_content_type.to_owned(), data)
    } else {
        let storage = storage(state)?;
        let (content_type, data) = storage.get_image(object_key).await.map_err(|error| {
            warn!(%error, %media_id, "image download from object storage failed");
            AppError::service_unavailable()
        })?;
        if data.len() <= state.config.redis_media_cache_max_bytes {
            cache::set_bytes(
                state,
                &cache_key,
                &data,
                state.config.redis_media_cache_ttl_seconds,
            )
            .await;
        }
        (content_type, data)
    };

    let content_type = HeaderValue::from_str(&content_type).map_err(AppError::internal)?;
    Ok((
        [
            (header::CONTENT_TYPE, content_type),
            (
                header::CACHE_CONTROL,
                HeaderValue::from_static(MEDIA_CACHE_CONTROL),
            ),
            (header::ETAG, etag_header),
        ],
        Body::from(data),
    )
        .into_response())
}

fn upload_validation(message: &str) -> AppError {
    AppError::validation(serde_json::json!({ "file": message }))
}

pub(crate) async fn extract_image(multipart: &mut Multipart) -> Result<UploadedImage, AppError> {
    let Some(field) = multipart
        .next_field()
        .await
        .map_err(|_| upload_validation("Не удалось прочитать файл"))?
    else {
        return Err(upload_validation("Выберите изображение"));
    };
    if field.name() != Some("file") {
        return Err(upload_validation("Ожидается поле file с изображением"));
    }
    let data = field
        .bytes()
        .await
        .map_err(|_| upload_validation("Не удалось прочитать файл"))?
        .to_vec();
    if data.is_empty() {
        return Err(upload_validation("Файл не должен быть пустым"));
    }
    if data.len() > MAX_IMAGE_BYTES {
        return Err(upload_validation(
            "Размер изображения не должен превышать 8 МБ",
        ));
    }
    let (content_type, extension) = detect_image_type(&data)
        .ok_or_else(|| upload_validation("Поддерживаются только JPEG, PNG и WebP"))?;
    Ok(UploadedImage {
        content_type,
        extension,
        data,
    })
}

fn detect_image_type(data: &[u8]) -> Option<(&'static str, &'static str)> {
    if data.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some(("image/jpeg", "jpg"))
    } else if data.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some(("image/png", "png"))
    } else if data.len() >= 12 && &data[0..4] == b"RIFF" && &data[8..12] == b"WEBP" {
        Some(("image/webp", "webp"))
    } else {
        None
    }
}

async fn persist_photo_row(
    state: &AppState,
    user_id: Uuid,
    photo_id: Uuid,
    object_key: &str,
    content_type: &str,
    bytes: i32,
    is_avatar: bool,
) -> Result<ProfilePhotoRow, AppError> {
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    let user_exists: Option<Uuid> =
        sqlx::query_scalar("SELECT id FROM users WHERE id = $1 AND status = 'active' FOR UPDATE")
            .bind(user_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(AppError::internal)?;
    if user_exists.is_none() {
        return Err(AppError::unauthorized(
            "UNAUTHORIZED",
            "Пользователь не найден",
        ));
    }

    if !is_avatar {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM user_photos WHERE user_id = $1 AND is_avatar = FALSE",
        )
        .bind(user_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(AppError::internal)?;
        if count >= MAX_GALLERY_PHOTOS {
            return Err(AppError {
                status: StatusCode::CONFLICT,
                code: "PHOTO_LIMIT_REACHED",
                message: "Можно добавить не более 12 личных фотографий".into(),
                fields: None,
            });
        }
    }

    let photo: ProfilePhotoRow = if is_avatar {
        sqlx::query(
            "UPDATE user_photos SET is_current_avatar = FALSE WHERE user_id = $1 AND is_current_avatar = TRUE",
        )
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .map_err(AppError::internal)?;
        sqlx::query_as(
            "INSERT INTO user_photos (id, user_id, object_key, content_type, bytes, is_avatar, is_current_avatar) VALUES ($1, $2, $3, $4, $5, TRUE, TRUE) RETURNING id, object_key, content_type, bytes, is_avatar, is_current_avatar, description, 0::bigint AS like_count, FALSE AS is_liked, created_at",
        )
        .bind(photo_id)
        .bind(user_id)
        .bind(object_key)
        .bind(content_type)
        .bind(bytes)
        .fetch_one(&mut *tx)
        .await
        .map_err(AppError::internal)?
    } else {
        sqlx::query_as(
            "INSERT INTO user_photos (id, user_id, object_key, content_type, bytes, is_avatar, is_current_avatar) VALUES ($1, $2, $3, $4, $5, FALSE, FALSE) RETURNING id, object_key, content_type, bytes, is_avatar, is_current_avatar, description, 0::bigint AS like_count, FALSE AS is_liked, created_at",
        )
        .bind(photo_id)
        .bind(user_id)
        .bind(object_key)
        .bind(content_type)
        .bind(bytes)
        .fetch_one(&mut *tx)
        .await
        .map_err(AppError::internal)?
    };

    tx.commit().await.map_err(AppError::internal)?;
    Ok(photo)
}

async fn persist_photo(
    state: &AppState,
    user_id: Uuid,
    image: UploadedImage,
    is_avatar: bool,
) -> Result<ProfilePhotoResponse, AppError> {
    let storage = storage(state)?;
    let photo_id = Uuid::new_v4();
    let object_key = storage.profile_object_key(user_id, photo_id, image.extension);
    let bytes = i32::try_from(image.data.len()).map_err(AppError::internal)?;

    if !is_avatar {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM user_photos WHERE user_id = $1 AND is_avatar = FALSE",
        )
        .bind(user_id)
        .fetch_one(&state.db)
        .await
        .map_err(AppError::internal)?;
        if count >= MAX_GALLERY_PHOTOS {
            return Err(AppError {
                status: StatusCode::CONFLICT,
                code: "PHOTO_LIMIT_REACHED",
                message: "Можно добавить не более 12 личных фотографий".into(),
                fields: None,
            });
        }
    }

    storage
        .put_image(&object_key, image.content_type, image.data)
        .await
        .map_err(|error| {
            warn!(error = %error, "profile image upload to object storage failed");
            AppError::service_unavailable()
        })?;

    let photo = match persist_photo_row(
        state,
        user_id,
        photo_id,
        &object_key,
        image.content_type,
        bytes,
        is_avatar,
    )
    .await
    {
        Ok(result) => result,
        Err(error) => {
            if let Err(cleanup_error) = storage.delete(&object_key).await {
                warn!(error = %cleanup_error, object_key = %object_key, "failed to clean up unreferenced profile image");
            }
            return Err(error);
        }
    };
    invalidate_profile_media(state, user_id).await;
    Ok(photo.into())
}

#[utoipa::path(
    get, path = "/api/v1/users/me/photos", tag = "media", security(("bearer_auth" = [])),
    responses((status = 200, body = ProfilePhotosResponse), (status = 401, description = "Access token is invalid or expired"))
)]
pub async fn list_profile_photos(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<ApiResponse<ProfilePhotosResponse>>, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    let cache_key = profile_media_cache_key(user_id);
    if let Some(cached) = cache::get_json::<ProfilePhotosResponse>(&state, &cache_key).await {
        return Ok(Json(ApiResponse::new(cached)));
    }
    let rows: Vec<ProfilePhotoRow> = sqlx::query_as(
        "SELECT photo.id, photo.object_key, photo.content_type, photo.bytes, photo.is_avatar, photo.is_current_avatar, photo.description, (SELECT COUNT(*) FROM profile_photo_likes likes WHERE likes.photo_id = photo.id) AS like_count, EXISTS(SELECT 1 FROM profile_photo_likes likes WHERE likes.photo_id = photo.id AND likes.user_id = $1) AS is_liked, photo.created_at FROM user_photos photo WHERE photo.user_id = $1 ORDER BY photo.is_current_avatar DESC, photo.is_avatar DESC, photo.created_at DESC",
    )
    .bind(user_id)
    .fetch_all(&state.db)
    .await
    .map_err(AppError::internal)?;
    let mut avatar = None;
    let mut avatars = Vec::new();
    let mut photos = Vec::new();
    for row in rows {
        if row.is_avatar {
            let response: ProfilePhotoResponse = row.into();
            if response.is_current_avatar {
                avatar = Some(response.clone());
            }
            avatars.push(response);
        } else {
            photos.push(row.into());
        }
    }
    let response = ProfilePhotosResponse {
        avatar,
        avatars,
        photos,
    };
    cache::set_json(
        &state,
        &cache_key,
        &response,
        state.config.redis_profile_cache_ttl_seconds,
    )
    .await;
    Ok(Json(ApiResponse::new(response)))
}

#[utoipa::path(
    post, path = "/api/v1/users/me/avatar", tag = "media", security(("bearer_auth" = [])),
    request_body(content = String, content_type = "multipart/form-data", description = "A single image in field file"),
    responses((status = 200, body = ProfilePhotoResponse), (status = 422, description = "Invalid image"), (status = 503, description = "Object storage is not configured or unavailable"))
)]
pub async fn upload_avatar(
    State(state): State<AppState>,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> Result<Json<ApiResponse<ProfilePhotoResponse>>, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    let image = extract_image(&mut multipart).await?;
    let photo = persist_photo(&state, user_id, image, true).await?;
    Ok(Json(ApiResponse::new(photo)))
}

#[utoipa::path(
    post, path = "/api/v1/users/me/photos", tag = "media", security(("bearer_auth" = [])),
    request_body(content = String, content_type = "multipart/form-data", description = "A single image in field file"),
    responses((status = 201, body = ProfilePhotoResponse), (status = 409, description = "Gallery contains 12 photos"), (status = 422, description = "Invalid image"), (status = 503, description = "Object storage is not configured or unavailable"))
)]
pub async fn upload_profile_photo(
    State(state): State<AppState>,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<ApiResponse<ProfilePhotoResponse>>), AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    let image = extract_image(&mut multipart).await?;
    let photo = persist_photo(&state, user_id, image, false).await?;
    Ok((StatusCode::CREATED, Json(ApiResponse::new(photo))))
}

#[utoipa::path(
    get, path = "/api/v1/users/me/photos/{photo_id}/content", tag = "media", security(("bearer_auth" = [])),
    params(("photo_id" = Uuid, Path, description = "Photo ID")),
    responses((status = 200, description = "Image bytes"), (status = 404, description = "Photo not found"), (status = 503, description = "Object storage is unavailable"))
)]
pub async fn download_profile_photo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(photo_id): Path<Uuid>,
) -> Result<Response, AppError> {
    let _viewer_id = active_user_id(&headers, &state).await?;
    let photo: Option<ProfilePhotoRow> = sqlx::query_as(
        "SELECT id, object_key, content_type, bytes, is_avatar, is_current_avatar, description, 0::bigint AS like_count, FALSE AS is_liked, created_at FROM user_photos WHERE id = $1",
    )
    .bind(photo_id)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?;
    let photo = photo.ok_or_else(|| AppError {
        status: StatusCode::NOT_FOUND,
        code: "PHOTO_NOT_FOUND",
        message: "Фотография не найдена".into(),
        fields: None,
    })?;
    cached_image_response(
        &state,
        &headers,
        &photo.object_key,
        &photo.content_type,
        photo.id,
    )
    .await
}

#[utoipa::path(
    delete, path = "/api/v1/users/me/photos/{photo_id}", tag = "media", security(("bearer_auth" = [])),
    params(("photo_id" = Uuid, Path, description = "Photo ID")),
    responses((status = 204, description = "Photo deleted"), (status = 404, description = "Photo not found"), (status = 401, description = "Access token is invalid or expired"))
)]
pub async fn delete_profile_photo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(photo_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    let mut tx = state.db.begin().await.map_err(AppError::internal)?;
    let photo: Option<ProfilePhotoRow> = sqlx::query_as(
        "DELETE FROM user_photos WHERE id = $1 AND user_id = $2 RETURNING id, object_key, content_type, bytes, is_avatar, is_current_avatar, description, 0::bigint AS like_count, FALSE AS is_liked, created_at",
    )
    .bind(photo_id)
    .bind(user_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(AppError::internal)?;
    let photo = photo.ok_or_else(|| AppError {
        status: StatusCode::NOT_FOUND,
        code: "PHOTO_NOT_FOUND",
        message: "Фотография не найдена".into(),
        fields: None,
    })?;
    if photo.is_current_avatar {
        sqlx::query(
            "UPDATE user_photos SET is_current_avatar = TRUE WHERE id = (SELECT id FROM user_photos WHERE user_id = $1 AND is_avatar = TRUE ORDER BY created_at DESC LIMIT 1)",
        )
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .map_err(AppError::internal)?;
    }
    tx.commit().await.map_err(AppError::internal)?;
    invalidate_profile_media(&state, user_id).await;
    invalidate_cached_image(&state, &photo.object_key).await;
    if let Some(storage) = state.object_storage.clone()
        && let Err(error) = storage.delete(&photo.object_key).await
    {
        warn!(error = %error, photo_id = %photo.id, "profile image was deleted from database but not object storage");
    }
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(
    patch, path = "/api/v1/users/me/photos/{photo_id}", tag = "media", security(("bearer_auth" = [])),
    request_body = UpdatePhotoRequest,
    params(("photo_id" = Uuid, Path, description = "Photo ID")),
    responses((status = 200, body = ProfilePhotoResponse), (status = 404, description = "Photo not found"), (status = 422, description = "Description is too long"))
)]
pub async fn update_profile_photo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(photo_id): Path<Uuid>,
    Json(request): Json<UpdatePhotoRequest>,
) -> Result<Json<ApiResponse<ProfilePhotoResponse>>, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    let description = request
        .description
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty());
    if description
        .as_ref()
        .is_some_and(|value| value.chars().count() > 500)
    {
        return Err(AppError::validation(serde_json::json!({
            "description": "Описание не должно быть длиннее 500 символов"
        })));
    }
    let photo: Option<ProfilePhotoRow> = sqlx::query_as(
        "UPDATE user_photos photo SET description = $3 WHERE photo.id = $1 AND photo.user_id = $2 RETURNING photo.id, photo.object_key, photo.content_type, photo.bytes, photo.is_avatar, photo.is_current_avatar, photo.description, (SELECT COUNT(*) FROM profile_photo_likes likes WHERE likes.photo_id = photo.id) AS like_count, EXISTS(SELECT 1 FROM profile_photo_likes likes WHERE likes.photo_id = photo.id AND likes.user_id = $2) AS is_liked, photo.created_at",
    )
    .bind(photo_id)
    .bind(user_id)
    .bind(description)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?;
    let photo = photo.ok_or_else(|| AppError {
        status: StatusCode::NOT_FOUND,
        code: "PHOTO_NOT_FOUND",
        message: "Фотография не найдена".into(),
        fields: None,
    })?;
    invalidate_profile_media(&state, user_id).await;
    Ok(Json(ApiResponse::new(photo.into())))
}

async fn set_photo_like(
    state: AppState,
    headers: HeaderMap,
    photo_id: Uuid,
    liked: bool,
) -> Result<Json<ApiResponse<PhotoEngagementResponse>>, AppError> {
    let user_id = active_user_id(&headers, &state).await?;
    let owner_id: Option<Uuid> =
        sqlx::query_scalar("SELECT user_id FROM user_photos WHERE id = $1")
            .bind(photo_id)
            .fetch_optional(&state.db)
            .await
            .map_err(AppError::internal)?;
    let Some(owner_id) = owner_id else {
        return Err(AppError {
            status: StatusCode::NOT_FOUND,
            code: "PHOTO_NOT_FOUND",
            message: "Фотография не найдена".into(),
            fields: None,
        });
    };
    if liked {
        sqlx::query("INSERT INTO profile_photo_likes (photo_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING")
            .bind(photo_id)
            .bind(user_id)
            .execute(&state.db)
            .await
            .map_err(AppError::internal)?;
    } else {
        sqlx::query("DELETE FROM profile_photo_likes WHERE photo_id = $1 AND user_id = $2")
            .bind(photo_id)
            .bind(user_id)
            .execute(&state.db)
            .await
            .map_err(AppError::internal)?;
    }
    let like_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM profile_photo_likes WHERE photo_id = $1")
            .bind(photo_id)
            .fetch_one(&state.db)
            .await
            .map_err(AppError::internal)?;
    invalidate_profile_media(&state, user_id).await;
    if owner_id != user_id {
        invalidate_profile_media(&state, owner_id).await;
    }
    Ok(Json(ApiResponse::new(PhotoEngagementResponse {
        photo_id,
        like_count,
        is_liked: liked,
    })))
}

pub async fn like_profile_photo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(photo_id): Path<Uuid>,
) -> Result<Json<ApiResponse<PhotoEngagementResponse>>, AppError> {
    set_photo_like(state, headers, photo_id, true).await
}

pub async fn unlike_profile_photo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(photo_id): Path<Uuid>,
) -> Result<Json<ApiResponse<PhotoEngagementResponse>>, AppError> {
    set_photo_like(state, headers, photo_id, false).await
}

#[cfg(test)]
mod tests {
    use super::detect_image_type;

    #[test]
    fn recognizes_supported_image_signatures() {
        assert_eq!(
            detect_image_type(&[0xFF, 0xD8, 0xFF]),
            Some(("image/jpeg", "jpg"))
        );
        assert_eq!(
            detect_image_type(b"\x89PNG\r\n\x1a\nrest"),
            Some(("image/png", "png"))
        );
        assert_eq!(
            detect_image_type(b"RIFF1234WEBPdata"),
            Some(("image/webp", "webp"))
        );
        assert_eq!(detect_image_type(b"not an image"), None);
    }
}
