use axum::{
    Json,
    body::Body,
    extract::{Multipart, Path, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::FromRow;
use tracing::warn;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::{
    app::AppState,
    infrastructure::storage::S3ObjectStorage,
    shared::{errors::AppError, response::ApiResponse},
};

use super::users::active_user_id;

pub const MAX_IMAGE_BYTES: usize = 8 * 1024 * 1024;
pub const MAX_MULTIPART_BODY_BYTES: usize = MAX_IMAGE_BYTES + 64 * 1024;
const MAX_GALLERY_PHOTOS: i64 = 12;

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ProfilePhotoResponse {
    pub id: Uuid,
    pub content_type: String,
    pub bytes: i32,
    pub created_at: DateTime<Utc>,
    pub content_path: String,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ProfilePhotosResponse {
    pub avatar: Option<ProfilePhotoResponse>,
    pub photos: Vec<ProfilePhotoResponse>,
}

#[derive(FromRow)]
struct ProfilePhotoRow {
    id: Uuid,
    object_key: String,
    content_type: String,
    bytes: i32,
    is_avatar: bool,
    created_at: DateTime<Utc>,
}

impl From<ProfilePhotoRow> for ProfilePhotoResponse {
    fn from(value: ProfilePhotoRow) -> Self {
        Self {
            content_path: format!("users/me/photos/{}/content", value.id),
            id: value.id,
            content_type: value.content_type,
            bytes: value.bytes,
            created_at: value.created_at,
        }
    }
}

struct UploadedImage {
    content_type: &'static str,
    extension: &'static str,
    data: Vec<u8>,
}

fn storage(state: &AppState) -> Result<S3ObjectStorage, AppError> {
    state.object_storage.clone().ok_or_else(|| AppError {
        status: StatusCode::SERVICE_UNAVAILABLE,
        code: "OBJECT_STORAGE_UNAVAILABLE",
        message: "Хранилище фотографий пока не настроено".into(),
        fields: None,
    })
}

fn upload_validation(message: &str) -> AppError {
    AppError::validation(serde_json::json!({ "file": message }))
}

async fn extract_image(multipart: &mut Multipart) -> Result<UploadedImage, AppError> {
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
) -> Result<(ProfilePhotoRow, Option<String>), AppError> {
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

    let previous_avatar_key = if is_avatar {
        sqlx::query_scalar::<_, String>(
            "SELECT object_key FROM user_photos WHERE user_id = $1 AND is_avatar = TRUE",
        )
        .bind(user_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(AppError::internal)?
    } else {
        None
    };

    let photo: ProfilePhotoRow = if is_avatar {
        sqlx::query_as(
            "INSERT INTO user_photos (id, user_id, object_key, content_type, bytes, is_avatar) VALUES ($1, $2, $3, $4, $5, TRUE) ON CONFLICT (user_id) WHERE is_avatar DO UPDATE SET id = EXCLUDED.id, object_key = EXCLUDED.object_key, content_type = EXCLUDED.content_type, bytes = EXCLUDED.bytes, created_at = NOW() RETURNING id, object_key, content_type, bytes, is_avatar, created_at",
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
            "INSERT INTO user_photos (id, user_id, object_key, content_type, bytes, is_avatar) VALUES ($1, $2, $3, $4, $5, FALSE) RETURNING id, object_key, content_type, bytes, is_avatar, created_at",
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
    Ok((photo, previous_avatar_key))
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

    let (photo, previous_avatar_key) = match persist_photo_row(
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
    if let Some(previous_avatar_key) = previous_avatar_key
        && previous_avatar_key != object_key
        && let Err(error) = storage.delete(&previous_avatar_key).await
    {
        warn!(error = %error, object_key = %previous_avatar_key, "failed to remove replaced avatar from object storage");
    }
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
    let _ = storage(&state)?;
    let user_id = active_user_id(&headers, &state).await?;
    let rows: Vec<ProfilePhotoRow> = sqlx::query_as(
        "SELECT id, object_key, content_type, bytes, is_avatar, created_at FROM user_photos WHERE user_id = $1 ORDER BY is_avatar DESC, created_at DESC",
    )
    .bind(user_id)
    .fetch_all(&state.db)
    .await
    .map_err(AppError::internal)?;
    let mut avatar = None;
    let mut photos = Vec::new();
    for row in rows {
        if row.is_avatar {
            avatar = Some(row.into());
        } else {
            photos.push(row.into());
        }
    }
    Ok(Json(ApiResponse::new(ProfilePhotosResponse {
        avatar,
        photos,
    })))
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
    let user_id = active_user_id(&headers, &state).await?;
    let photo: Option<ProfilePhotoRow> = sqlx::query_as(
        "SELECT id, object_key, content_type, bytes, is_avatar, created_at FROM user_photos WHERE id = $1 AND user_id = $2",
    )
    .bind(photo_id)
    .bind(user_id)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?;
    let photo = photo.ok_or_else(|| AppError {
        status: StatusCode::NOT_FOUND,
        code: "PHOTO_NOT_FOUND",
        message: "Фотография не найдена".into(),
        fields: None,
    })?;
    let storage = storage(&state)?;
    let (content_type, data) = storage.get_image(&photo.object_key).await.map_err(|error| {
        warn!(error = %error, photo_id = %photo.id, "profile image download from object storage failed");
        AppError::service_unavailable()
    })?;
    let content_type = HeaderValue::from_str(&content_type).map_err(AppError::internal)?;
    Ok((
        [
            (header::CONTENT_TYPE, content_type),
            (
                header::CACHE_CONTROL,
                HeaderValue::from_static("private, max-age=3600"),
            ),
        ],
        Body::from(data),
    )
        .into_response())
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
    let photo: Option<ProfilePhotoRow> = sqlx::query_as(
        "DELETE FROM user_photos WHERE id = $1 AND user_id = $2 RETURNING id, object_key, content_type, bytes, is_avatar, created_at",
    )
    .bind(photo_id)
    .bind(user_id)
    .fetch_optional(&state.db)
    .await
    .map_err(AppError::internal)?;
    let photo = photo.ok_or_else(|| AppError {
        status: StatusCode::NOT_FOUND,
        code: "PHOTO_NOT_FOUND",
        message: "Фотография не найдена".into(),
        fields: None,
    })?;
    if let Some(storage) = state.object_storage.clone()
        && let Err(error) = storage.delete(&photo.object_key).await
    {
        warn!(error = %error, photo_id = %photo.id, "profile image was deleted from database but not object storage");
    }
    Ok(StatusCode::NO_CONTENT)
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
