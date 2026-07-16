use argon2::{
    Argon2, PasswordHash, PasswordHasher, PasswordVerifier,
    password_hash::{SaltString, rand_core::OsRng},
};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use chrono::{DateTime, Duration, Utc};
use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header, Validation, decode, encode};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::shared::errors::AppError;

#[derive(Debug, Serialize, Deserialize)]
struct AccessClaims {
    sub: Uuid,
    exp: usize,
    iat: usize,
    token_type: String,
}

pub fn hash_password(password: &str) -> Result<String, AppError> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|value| value.to_string())
        .map_err(AppError::internal)
}

pub fn verify_password(password: &str, hash: &str) -> bool {
    PasswordHash::new(hash).ok().is_some_and(|parsed| {
        Argon2::default()
            .verify_password(password.as_bytes(), &parsed)
            .is_ok()
    })
}

pub fn issue_access_token(
    user_id: Uuid,
    secret: &str,
    ttl_seconds: i64,
) -> Result<(String, DateTime<Utc>), AppError> {
    let now = Utc::now();
    let expires_at = now + Duration::seconds(ttl_seconds);
    let claims = AccessClaims {
        sub: user_id,
        exp: expires_at.timestamp() as usize,
        iat: now.timestamp() as usize,
        token_type: "access".into(),
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .map(|token| (token, expires_at))
    .map_err(AppError::internal)
}

pub fn verify_access_token(token: &str, secret: &str) -> Result<Uuid, AppError> {
    let mut validation = Validation::new(Algorithm::HS256);
    validation.set_required_spec_claims(&["exp", "sub"]);
    match decode::<AccessClaims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &validation,
    ) {
        Ok(data) if data.claims.token_type == "access" => Ok(data.claims.sub),
        Ok(_) => Err(AppError::unauthorized(
            "UNAUTHORIZED",
            "Недействительный access token",
        )),
        Err(error)
            if matches!(
                error.kind(),
                jsonwebtoken::errors::ErrorKind::ExpiredSignature
            ) =>
        {
            Err(AppError::unauthorized(
                "TOKEN_EXPIRED",
                "Срок действия access token истёк",
            ))
        }
        Err(_) => Err(AppError::unauthorized(
            "UNAUTHORIZED",
            "Недействительный access token",
        )),
    }
}

pub fn generate_refresh_token() -> String {
    let mut bytes = [0u8; 48];
    rand::thread_rng().fill_bytes(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

pub fn refresh_token_hash(token: &str, secret: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(secret.as_bytes());
    hasher.update(token.as_bytes());
    format!("{:x}", hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn password_hash_never_contains_plaintext_and_verifies() {
        let password = "StrongPassword123";
        let hash = hash_password(password).expect("hash password");
        assert_ne!(hash, password);
        assert!(verify_password(password, &hash));
        assert!(!verify_password("wrong-password", &hash));
    }

    #[test]
    fn access_token_is_bound_to_its_user() {
        let user_id = Uuid::new_v4();
        let (token, _) = issue_access_token(user_id, "test-secret", 60).expect("issue token");
        assert_eq!(
            verify_access_token(&token, "test-secret").expect("verify token"),
            user_id
        );
        assert!(verify_access_token(&token, "another-secret").is_err());
    }

    #[test]
    fn refresh_tokens_are_random_and_only_hash_is_stable() {
        let first = generate_refresh_token();
        let second = generate_refresh_token();
        assert_ne!(first, second);
        assert_eq!(
            refresh_token_hash(&first, "secret"),
            refresh_token_hash(&first, "secret")
        );
        assert_ne!(
            refresh_token_hash(&first, "secret"),
            refresh_token_hash(&second, "secret")
        );
    }
}
