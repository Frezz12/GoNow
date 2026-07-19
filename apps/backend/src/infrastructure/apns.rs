use std::sync::{Arc, Mutex};

use chrono::Utc;
use jsonwebtoken::{Algorithm, EncodingKey, Header, encode};
use reqwest::{Client, StatusCode};
use serde::{Deserialize, Serialize};
use serde_json::json;
use thiserror::Error;
use uuid::Uuid;

use crate::config::ApnsConfig;

#[derive(Clone)]
pub struct ApnsClient {
    http: Client,
    team_id: String,
    key_id: String,
    bundle_id: String,
    host: String,
    encoding_key: Arc<EncodingKey>,
    auth_token: Arc<Mutex<Option<CachedAuthToken>>>,
}

#[derive(Clone)]
struct CachedAuthToken {
    value: String,
    issued_at: i64,
}

#[derive(Debug, Clone)]
pub struct ApnsPush<'a> {
    pub notification_id: Uuid,
    pub title: &'a str,
    pub body: &'a str,
    pub badge: i64,
    pub category: &'a str,
    pub kind: &'a str,
    pub entity_type: Option<&'a str>,
    pub entity_id: Option<Uuid>,
    pub action_path: Option<&'a str>,
    pub sound: bool,
}

#[derive(Debug, Error)]
pub enum ApnsError {
    #[error("invalid APNs device token")]
    InvalidToken,
    #[error("APNs authentication failed: {0}")]
    Authentication(String),
    #[error("APNs request failed: {0}")]
    Request(String),
}

#[derive(Serialize)]
struct ProviderClaims<'a> {
    iss: &'a str,
    iat: i64,
}

#[derive(Deserialize)]
struct ApnsErrorBody {
    reason: Option<String>,
}

impl ApnsClient {
    pub fn new(config: &ApnsConfig) -> Result<Self, String> {
        let encoding_key = EncodingKey::from_ec_pem(config.private_key_pem.as_bytes())
            .map_err(|_| "APNS_PRIVATE_KEY_BASE64 contains an invalid Apple .p8 key".to_string())?;
        let http = Client::builder()
            .http2_adaptive_window(true)
            .build()
            .map_err(|error| format!("unable to create APNs HTTP client: {error}"))?;
        let host = apns_host(&config.environment);
        Ok(Self {
            http,
            team_id: config.team_id.clone(),
            key_id: config.key_id.clone(),
            bundle_id: config.bundle_id.clone(),
            host: host.into(),
            encoding_key: Arc::new(encoding_key),
            auth_token: Arc::new(Mutex::new(None)),
        })
    }

    pub async fn send(&self, device_token: &str, push: &ApnsPush<'_>) -> Result<(), ApnsError> {
        let token = self.provider_token()?;
        let mut aps = json!({
            "alert": {"title": push.title, "body": push.body},
            "badge": push.badge,
            "thread-id": push.category
        });
        if push.sound {
            aps["sound"] = json!("default");
        }
        let payload = json!({
            "aps": aps,
            "notificationId": push.notification_id,
            "category": push.category,
            "kind": push.kind,
            "entityType": push.entity_type,
            "entityId": push.entity_id,
            "actionPath": push.action_path
        });
        let response = self
            .http
            .post(format!("{}/3/device/{device_token}", self.host))
            .bearer_auth(token)
            .header("apns-topic", &self.bundle_id)
            .header("apns-push-type", "alert")
            .header("apns-priority", "10")
            .header("apns-expiration", "0")
            .header("apns-id", push.notification_id.to_string())
            .json(&payload)
            .send()
            .await
            .map_err(|error| ApnsError::Request(error.to_string()))?;
        if response.status().is_success() {
            return Ok(());
        }
        let status = response.status();
        let body = response.json::<ApnsErrorBody>().await.ok();
        let reason = body
            .and_then(|value| value.reason)
            .unwrap_or_else(|| format!("HTTP {}", status.as_u16()));
        if status == StatusCode::GONE
            || matches!(
                reason.as_str(),
                "BadDeviceToken" | "DeviceTokenNotForTopic" | "Unregistered"
            )
        {
            Err(ApnsError::InvalidToken)
        } else {
            Err(ApnsError::Request(reason))
        }
    }

    fn provider_token(&self) -> Result<String, ApnsError> {
        let now = Utc::now().timestamp();
        let mut cached = self
            .auth_token
            .lock()
            .map_err(|_| ApnsError::Authentication("token cache is unavailable".into()))?;
        if let Some(token) = cached.as_ref()
            && now - token.issued_at < 45 * 60
        {
            return Ok(token.value.clone());
        }
        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(self.key_id.clone());
        let value = encode(
            &header,
            &ProviderClaims {
                iss: &self.team_id,
                iat: now,
            },
            &self.encoding_key,
        )
        .map_err(|error| ApnsError::Authentication(error.to_string()))?;
        *cached = Some(CachedAuthToken {
            value: value.clone(),
            issued_at: now,
        });
        Ok(value)
    }
}

fn apns_host(environment: &str) -> &'static str {
    if environment == "production" {
        "https://api.push.apple.com"
    } else {
        "https://api.sandbox.push.apple.com"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sandbox_and_production_hosts_are_selected_explicitly() {
        assert_eq!(apns_host("sandbox"), "https://api.sandbox.push.apple.com");
        assert_eq!(apns_host("production"), "https://api.push.apple.com");
    }
}
