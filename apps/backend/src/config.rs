use std::env;

use axum::http::HeaderValue;
use base64::{Engine as _, engine::general_purpose::STANDARD};

#[derive(Clone)]
pub struct Config {
    pub app_env: String,
    pub host: String,
    pub port: u16,
    pub database_url: String,
    pub redis_url: String,
    pub redis_media_cache_ttl_seconds: u64,
    pub redis_media_cache_max_bytes: usize,
    pub redis_profile_cache_ttl_seconds: u64,
    pub redis_weather_cache_ttl_seconds: u64,
    pub redis_user_status_cache_ttl_seconds: u64,
    pub jwt_access_secret: String,
    pub jwt_refresh_secret: String,
    pub jwt_access_ttl_seconds: i64,
    pub jwt_refresh_ttl_seconds: i64,
    pub password_min_length: usize,
    pub cors_allowed_origins: Vec<HeaderValue>,
    pub rate_limit_register_max: i64,
    pub rate_limit_login_max: i64,
    pub rate_limit_refresh_max: i64,
    pub rate_limit_window_seconds: i64,
    pub resend_api_key: Option<String>,
    pub resend_from_email: Option<String>,
    pub email_code_ttl_seconds: i64,
    pub object_storage: Option<ObjectStorageConfig>,
    pub apns: Option<ApnsConfig>,
}

/// Generic S3-compatible configuration. Cloudflare R2 is only one possible
/// provider; no provider-specific value is stored in the application code.
#[derive(Clone)]
pub struct ObjectStorageConfig {
    pub endpoint: Option<String>,
    pub bucket: String,
    pub access_key_id: String,
    pub secret_access_key: String,
    pub region: String,
    pub key_prefix: String,
    pub force_path_style: bool,
}

#[derive(Clone)]
pub struct ApnsConfig {
    pub team_id: String,
    pub key_id: String,
    pub private_key_pem: String,
    pub bundle_id: String,
    pub environment: String,
}

impl Config {
    pub fn from_environment() -> Result<Self, String> {
        const MAX_DURATION_SECONDS: i64 = 10 * 365 * 24 * 60 * 60;
        let required = |key: &str| {
            env::var(key).map_err(|_| format!("missing required environment variable {key}"))
        };
        let optional =
            |key: &str, fallback: &str| env::var(key).unwrap_or_else(|_| fallback.to_owned());
        let parse = |key: &str, fallback: &str| -> Result<i64, String> {
            optional(key, fallback)
                .parse()
                .map_err(|_| format!("{key} must be a number"))
        };
        let parse_positive = |key: &str, fallback: &str| -> Result<i64, String> {
            let value = parse(key, fallback)?;
            if value <= 0 {
                return Err(format!("{key} must be greater than zero"));
            }
            Ok(value)
        };

        let jwt_access_secret = required("JWT_ACCESS_SECRET")?;
        let jwt_refresh_secret = required("JWT_REFRESH_SECRET")?;
        if jwt_access_secret.len() < 32 || jwt_refresh_secret.len() < 32 {
            return Err("JWT secrets must contain at least 32 bytes".into());
        }
        if jwt_access_secret == jwt_refresh_secret {
            return Err("JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must be different".into());
        }

        let jwt_access_ttl_seconds = parse_positive("JWT_ACCESS_TTL_SECONDS", "900")?;
        let jwt_refresh_ttl_seconds = parse_positive("JWT_REFRESH_TTL_SECONDS", "2592000")?;
        let email_code_ttl_seconds = parse_positive("EMAIL_CODE_TTL_SECONDS", "600")?;
        if [
            jwt_access_ttl_seconds,
            jwt_refresh_ttl_seconds,
            email_code_ttl_seconds,
        ]
        .into_iter()
        .any(|value| value > MAX_DURATION_SECONDS)
        {
            return Err("token and email-code lifetimes must not exceed 10 years".into());
        }

        let password_min_length = parse_positive("PASSWORD_MIN_LENGTH", "8")?;
        if !(8..=128).contains(&password_min_length) {
            return Err("PASSWORD_MIN_LENGTH must be between 8 and 128".into());
        }

        let cors_allowed_origins = optional("CORS_ALLOWED_ORIGINS", "")
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(|origin| {
                origin
                    .parse::<HeaderValue>()
                    .map_err(|_| format!("invalid CORS origin: {origin}"))
            })
            .collect::<Result<Vec<_>, _>>()?;
        let object_storage = ObjectStorageConfig::from_environment()?;
        let apns = ApnsConfig::from_environment()?;
        let redis_media_cache_max_bytes = parse_positive("REDIS_MEDIA_CACHE_MAX_BYTES", "4194304")?;
        if redis_media_cache_max_bytes > 16 * 1024 * 1024 {
            return Err("REDIS_MEDIA_CACHE_MAX_BYTES must not exceed 16777216".into());
        }
        Ok(Self {
            app_env: optional("APP_ENV", "development"),
            host: optional("APP_HOST", "0.0.0.0"),
            port: optional("APP_PORT", "8080")
                .parse()
                .map_err(|_| "APP_PORT must be a number".to_string())?,
            database_url: required("DATABASE_URL")?,
            redis_url: required("REDIS_URL")?,
            redis_media_cache_ttl_seconds: parse_positive("REDIS_MEDIA_CACHE_TTL_SECONDS", "86400")?
                as u64,
            redis_media_cache_max_bytes: redis_media_cache_max_bytes as usize,
            redis_profile_cache_ttl_seconds: parse_positive(
                "REDIS_PROFILE_CACHE_TTL_SECONDS",
                "60",
            )? as u64,
            redis_weather_cache_ttl_seconds: parse_positive(
                "REDIS_WEATHER_CACHE_TTL_SECONDS",
                "300",
            )? as u64,
            redis_user_status_cache_ttl_seconds: parse_positive(
                "REDIS_USER_STATUS_CACHE_TTL_SECONDS",
                "30",
            )? as u64,
            jwt_access_secret,
            jwt_refresh_secret,
            jwt_access_ttl_seconds,
            jwt_refresh_ttl_seconds,
            password_min_length: password_min_length as usize,
            cors_allowed_origins,
            rate_limit_register_max: parse_positive("RATE_LIMIT_REGISTER_MAX", "5")?,
            rate_limit_login_max: parse_positive("RATE_LIMIT_LOGIN_MAX", "10")?,
            rate_limit_refresh_max: parse_positive("RATE_LIMIT_REFRESH_MAX", "30")?,
            rate_limit_window_seconds: parse_positive("RATE_LIMIT_WINDOW_SECONDS", "900")?,
            resend_api_key: env::var("RESEND_API_KEY")
                .ok()
                .filter(|value| !value.is_empty()),
            resend_from_email: env::var("RESEND_FROM_EMAIL")
                .ok()
                .filter(|value| !value.is_empty()),
            email_code_ttl_seconds,
            object_storage,
            apns,
        })
    }
}

impl ApnsConfig {
    fn from_environment() -> Result<Option<Self>, String> {
        const KEYS: [&str; 4] = [
            "APNS_TEAM_ID",
            "APNS_KEY_ID",
            "APNS_PRIVATE_KEY_BASE64",
            "APNS_BUNDLE_ID",
        ];
        let values = KEYS.map(|key| env::var(key).unwrap_or_default().trim().to_owned());
        let supplied = values.iter().filter(|value| !value.is_empty()).count();
        if supplied == 0 {
            return Ok(None);
        }
        if supplied != KEYS.len() {
            let missing = KEYS
                .iter()
                .zip(values.iter())
                .filter_map(|(key, value)| value.is_empty().then_some(*key))
                .collect::<Vec<_>>()
                .join(", ");
            return Err(format!(
                "APNs is partially configured; missing required variable(s): {missing}"
            ));
        }
        let private_key = STANDARD
            .decode(&values[2])
            .map_err(|_| "APNS_PRIVATE_KEY_BASE64 must be valid base64".to_string())?;
        let private_key_pem = String::from_utf8(private_key)
            .map_err(|_| "APNS_PRIVATE_KEY_BASE64 must contain a UTF-8 .p8 key".to_string())?;
        if !private_key_pem.contains("BEGIN PRIVATE KEY") {
            return Err("APNS_PRIVATE_KEY_BASE64 must contain an Apple .p8 private key".into());
        }
        let environment = env::var("APNS_ENVIRONMENT")
            .unwrap_or_else(|_| "sandbox".into())
            .trim()
            .to_owned();
        if !matches!(environment.as_str(), "sandbox" | "production") {
            return Err("APNS_ENVIRONMENT must be sandbox or production".into());
        }
        Ok(Some(Self {
            team_id: values[0].clone(),
            key_id: values[1].clone(),
            private_key_pem,
            bundle_id: values[3].clone(),
            environment,
        }))
    }
}

impl ObjectStorageConfig {
    fn from_environment() -> Result<Option<Self>, String> {
        const REQUIRED: [&str; 3] = [
            "OBJECT_STORAGE_BUCKET",
            "OBJECT_STORAGE_ACCESS_KEY_ID",
            "OBJECT_STORAGE_SECRET_ACCESS_KEY",
        ];
        let supplied = REQUIRED
            .iter()
            .filter(|key| {
                env::var(key)
                    .ok()
                    .is_some_and(|value| !value.trim().is_empty())
            })
            .count();
        let endpoint_is_set = env::var("OBJECT_STORAGE_ENDPOINT")
            .ok()
            .is_some_and(|value| !value.trim().is_empty());
        if supplied == 0 && !endpoint_is_set {
            return Ok(None);
        }
        if supplied != REQUIRED.len() {
            let missing = REQUIRED
                .iter()
                .filter(|key| {
                    env::var(key)
                        .ok()
                        .is_none_or(|value| value.trim().is_empty())
                })
                .copied()
                .collect::<Vec<_>>()
                .join(", ");
            return Err(format!(
                "object storage is partially configured; missing required variable(s): {missing}"
            ));
        }

        let endpoint = env::var("OBJECT_STORAGE_ENDPOINT")
            .ok()
            .map(|value| value.trim_end_matches('/').to_owned())
            .filter(|value| !value.is_empty());
        if endpoint.as_ref().is_some_and(|endpoint| {
            !(endpoint.starts_with("https://") || endpoint.starts_with("http://"))
        }) {
            return Err(
                "OBJECT_STORAGE_ENDPOINT must start with http:// or https:// when set".into(),
            );
        }
        let key_prefix = env::var("OBJECT_STORAGE_KEY_PREFIX")
            .unwrap_or_else(|_| "gonow".into())
            .trim_matches('/')
            .to_owned();
        if key_prefix.is_empty() {
            return Err("OBJECT_STORAGE_KEY_PREFIX must not be empty".into());
        }
        Ok(Some(Self {
            endpoint,
            bucket: env::var("OBJECT_STORAGE_BUCKET")
                .expect("required object storage bucket was checked"),
            access_key_id: env::var("OBJECT_STORAGE_ACCESS_KEY_ID")
                .expect("required object storage access key was checked"),
            secret_access_key: env::var("OBJECT_STORAGE_SECRET_ACCESS_KEY")
                .expect("required object storage secret was checked"),
            region: env::var("OBJECT_STORAGE_REGION").unwrap_or_else(|_| "auto".into()),
            key_prefix,
            force_path_style: env::var("OBJECT_STORAGE_FORCE_PATH_STYLE")
                .unwrap_or_else(|_| "true".into())
                .parse()
                .map_err(|_| "OBJECT_STORAGE_FORCE_PATH_STYLE must be true or false")?,
        }))
    }
}
