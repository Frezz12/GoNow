use redis::AsyncCommands;
use serde::{Serialize, de::DeserializeOwned};
use tracing::warn;

use crate::app::AppState;

pub async fn get_json<T: DeserializeOwned>(state: &AppState, key: &str) -> Option<T> {
    let mut redis = state.redis.clone();
    let value = match redis.get::<_, Option<String>>(key).await {
        Ok(value) => value?,
        Err(error) => {
            warn!(%error, cache_key = key, "Redis cache read failed");
            return None;
        }
    };
    match serde_json::from_str(&value) {
        Ok(value) => Some(value),
        Err(error) => {
            warn!(%error, cache_key = key, "Redis JSON cache entry is invalid");
            None
        }
    }
}

pub async fn set_json<T: Serialize + ?Sized>(
    state: &AppState,
    key: &str,
    value: &T,
    ttl_seconds: u64,
) {
    let Ok(value) = serde_json::to_string(value) else {
        warn!(
            cache_key = key,
            "Redis JSON cache value could not be serialized"
        );
        return;
    };
    let mut redis = state.redis.clone();
    if let Err(error) = redis.set_ex::<_, _, ()>(key, value, ttl_seconds).await {
        warn!(%error, cache_key = key, "Redis cache write failed");
    }
}

pub async fn get_bytes(state: &AppState, key: &str) -> Option<Vec<u8>> {
    let mut redis = state.redis.clone();
    match redis.get::<_, Option<Vec<u8>>>(key).await {
        Ok(value) => value.filter(|value| !value.is_empty()),
        Err(error) => {
            warn!(%error, cache_key = key, "Redis binary cache read failed");
            None
        }
    }
}

pub async fn set_bytes(state: &AppState, key: &str, value: &[u8], ttl_seconds: u64) {
    let mut redis = state.redis.clone();
    if let Err(error) = redis.set_ex::<_, _, ()>(key, value, ttl_seconds).await {
        warn!(%error, cache_key = key, "Redis binary cache write failed");
    }
}

pub async fn delete(state: &AppState, key: &str) {
    let mut redis = state.redis.clone();
    if let Err(error) = redis.del::<_, ()>(key).await {
        warn!(%error, cache_key = key, "Redis cache invalidation failed");
    }
}
