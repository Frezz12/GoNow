use aws_config::{BehaviorVersion, Region};
use aws_credential_types::Credentials;
use aws_sdk_s3::{
    Client,
    config::Builder,
    error::{ProvideErrorMetadata, SdkError},
    primitives::ByteStream,
};
use thiserror::Error;

use crate::config::ObjectStorageConfig;

/// S3-compatible object storage boundary. R2, AWS S3, MinIO and most managed
/// object stores can be selected exclusively through environment variables.
#[derive(Clone)]
pub struct S3ObjectStorage {
    client: Client,
    bucket: String,
    key_prefix: String,
}

#[derive(Debug, Error)]
pub enum ObjectStorageError {
    #[error("object storage request failed: {0}")]
    Request(String),
}

/// Extract provider diagnostics without logging request headers or credentials.
/// `SdkError`'s Display implementation may only say "service error", while S3
/// providers put the useful reason in error metadata and the raw HTTP status.
fn describe_s3_error<E: ProvideErrorMetadata>(error: &SdkError<E>) -> String {
    let status = error
        .raw_response()
        .map(|response| response.status().as_u16())
        .map(|status| format!("HTTP {status}"));
    let (code, message) = error
        .as_service_error()
        .map(|service_error| (service_error.code(), service_error.message()))
        .unwrap_or((None, None));
    [
        status,
        code.map(|value| format!("code={value}")),
        message.map(|value| format!("message={value}")),
        Some(format!("kind={}", error)),
    ]
    .into_iter()
    .flatten()
    .collect::<Vec<_>>()
    .join(", ")
}

impl S3ObjectStorage {
    pub async fn connect(config: &ObjectStorageConfig) -> Self {
        let credentials = Credentials::new(
            &config.access_key_id,
            &config.secret_access_key,
            None,
            None,
            "gonow-object-storage",
        );
        let loader = aws_config::defaults(BehaviorVersion::latest())
            .region(Region::new(config.region.clone()))
            .credentials_provider(credentials);
        let sdk_config = match &config.endpoint {
            Some(endpoint) => loader.endpoint_url(endpoint).load().await,
            None => loader.load().await,
        };
        let s3_config = Builder::from(&sdk_config)
            .force_path_style(config.force_path_style)
            .build();
        Self {
            client: Client::from_conf(s3_config),
            bucket: config.bucket.clone(),
            key_prefix: config.key_prefix.clone(),
        }
    }

    pub fn profile_object_key(
        &self,
        user_id: uuid::Uuid,
        photo_id: uuid::Uuid,
        extension: &str,
    ) -> String {
        format!(
            "{}/profiles/{user_id}/{photo_id}.{extension}",
            self.key_prefix
        )
    }

    pub fn activity_object_key(
        &self,
        activity_id: uuid::Uuid,
        photo_id: uuid::Uuid,
        extension: &str,
    ) -> String {
        format!(
            "{}/activities/{activity_id}/{photo_id}.{extension}",
            self.key_prefix
        )
    }

    pub fn chat_object_key(
        &self,
        conversation_id: uuid::Uuid,
        message_id: uuid::Uuid,
        extension: &str,
    ) -> String {
        format!(
            "{}/chats/{conversation_id}/{message_id}.{extension}",
            self.key_prefix
        )
    }

    pub async fn put_image(
        &self,
        key: &str,
        content_type: &str,
        data: Vec<u8>,
    ) -> Result<(), ObjectStorageError> {
        self.client
            .put_object()
            .bucket(&self.bucket)
            .key(key)
            .content_type(content_type)
            .cache_control("private, max-age=86400")
            .body(ByteStream::from(data))
            .send()
            .await
            .map_err(|error| ObjectStorageError::Request(describe_s3_error(&error)))?;
        Ok(())
    }

    pub async fn get_image(&self, key: &str) -> Result<(String, Vec<u8>), ObjectStorageError> {
        let output = self
            .client
            .get_object()
            .bucket(&self.bucket)
            .key(key)
            .send()
            .await
            .map_err(|error| ObjectStorageError::Request(describe_s3_error(&error)))?;
        let content_type = output
            .content_type()
            .unwrap_or("application/octet-stream")
            .to_owned();
        let data = output
            .body
            .collect()
            .await
            .map_err(|error| ObjectStorageError::Request(error.to_string()))?
            .into_bytes()
            .to_vec();
        Ok((content_type, data))
    }

    pub async fn delete(&self, key: &str) -> Result<(), ObjectStorageError> {
        self.client
            .delete_object()
            .bucket(&self.bucket)
            .key(key)
            .send()
            .await
            .map_err(|error| ObjectStorageError::Request(describe_s3_error(&error)))?;
        Ok(())
    }
}
