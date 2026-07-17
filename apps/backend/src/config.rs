use std::env;

#[derive(Clone)]
pub struct Config {
    pub app_env: String,
    pub host: String,
    pub port: u16,
    pub database_url: String,
    pub redis_url: String,
    pub jwt_access_secret: String,
    pub jwt_refresh_secret: String,
    pub jwt_access_ttl_seconds: i64,
    pub jwt_refresh_ttl_seconds: i64,
    pub password_min_length: usize,
    pub cors_allowed_origins: Vec<String>,
    pub rate_limit_register_max: i64,
    pub rate_limit_login_max: i64,
    pub rate_limit_refresh_max: i64,
    pub rate_limit_window_seconds: i64,
    pub resend_api_key: Option<String>,
    pub resend_from_email: Option<String>,
    pub email_code_ttl_seconds: i64,
    pub object_storage: Option<ObjectStorageConfig>,
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

impl Config {
    pub fn from_environment() -> Result<Self, String> {
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
        let object_storage = ObjectStorageConfig::from_environment()?;
        Ok(Self {
            app_env: optional("APP_ENV", "development"),
            host: optional("APP_HOST", "0.0.0.0"),
            port: optional("APP_PORT", "8080")
                .parse()
                .map_err(|_| "APP_PORT must be a number".to_string())?,
            database_url: required("DATABASE_URL")?,
            redis_url: required("REDIS_URL")?,
            jwt_access_secret: required("JWT_ACCESS_SECRET")?,
            jwt_refresh_secret: required("JWT_REFRESH_SECRET")?,
            jwt_access_ttl_seconds: parse("JWT_ACCESS_TTL_SECONDS", "900")?,
            jwt_refresh_ttl_seconds: parse("JWT_REFRESH_TTL_SECONDS", "2592000")?,
            password_min_length: parse("PASSWORD_MIN_LENGTH", "8")? as usize,
            cors_allowed_origins: optional("CORS_ALLOWED_ORIGINS", "")
                .split(',')
                .filter(|v| !v.is_empty())
                .map(str::to_owned)
                .collect(),
            rate_limit_register_max: parse("RATE_LIMIT_REGISTER_MAX", "5")?,
            rate_limit_login_max: parse("RATE_LIMIT_LOGIN_MAX", "10")?,
            rate_limit_refresh_max: parse("RATE_LIMIT_REFRESH_MAX", "30")?,
            rate_limit_window_seconds: parse("RATE_LIMIT_WINDOW_SECONDS", "900")?,
            resend_api_key: env::var("RESEND_API_KEY")
                .ok()
                .filter(|value| !value.is_empty()),
            resend_from_email: env::var("RESEND_FROM_EMAIL")
                .ok()
                .filter(|value| !value.is_empty()),
            email_code_ttl_seconds: parse("EMAIL_CODE_TTL_SECONDS", "600")?,
            object_storage,
        })
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
