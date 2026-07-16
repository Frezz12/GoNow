use std::env;

#[derive(Clone, Debug)]
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
            resend_api_key: env::var("RESEND_API_KEY").ok().filter(|value| !value.is_empty()),
            resend_from_email: env::var("RESEND_FROM_EMAIL").ok().filter(|value| !value.is_empty()),
            email_code_ttl_seconds: parse("EMAIL_CODE_TTL_SECONDS", "600")?,
        })
    }
}
