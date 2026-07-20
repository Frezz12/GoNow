use std::time::Duration;

use redis::{AsyncCommands, FromRedisValue, RedisResult, ToRedisArgs};
use serde::{Serialize, de::DeserializeOwned};
use tokio::time::sleep;
use tracing::{debug, warn};

use crate::app::AppState;

pub async fn get_json<T: DeserializeOwned>(state: &AppState, key: &str) -> Option<T> {
    let value = match get_value::<String>(state, key).await {
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
            delete(state, key).await;
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
    if let Err(error) = set_value(state, key, value, ttl_seconds).await {
        warn!(%error, cache_key = key, "Redis cache write failed");
    }
}

pub async fn get_bytes(state: &AppState, key: &str) -> Option<Vec<u8>> {
    match get_value::<Vec<u8>>(state, key).await {
        Ok(value) => value.filter(|value| !value.is_empty()),
        Err(error) => {
            warn!(%error, cache_key = key, "Redis binary cache read failed");
            None
        }
    }
}

pub async fn set_bytes(state: &AppState, key: &str, value: &[u8], ttl_seconds: u64) {
    if let Err(error) = set_value(state, key, value.to_vec(), ttl_seconds).await {
        warn!(%error, cache_key = key, "Redis binary cache write failed");
    }
}

pub async fn delete(state: &AppState, key: &str) {
    if let Err(error) = delete_value(state, key).await {
        warn!(%error, cache_key = key, "Redis cache invalidation failed");
    }
}

async fn get_value<T>(state: &AppState, key: &str) -> RedisResult<Option<T>>
where
    T: FromRedisValue,
{
    let mut redis = state.redis.clone();
    match redis.get::<_, Option<T>>(key).await {
        Err(error) if error.is_io_error() => {
            debug!(%error, cache_key = key, "Redis connection dropped; retrying cache read");
            sleep(Duration::from_millis(75)).await;
            let mut redis = state.redis.clone();
            redis.get::<_, Option<T>>(key).await
        }
        result => result,
    }
}

async fn set_value<T>(state: &AppState, key: &str, value: T, ttl_seconds: u64) -> RedisResult<()>
where
    T: ToRedisArgs + Clone + Send + Sync,
{
    let mut redis = state.redis.clone();
    match redis
        .set_ex::<_, _, ()>(key, value.clone(), ttl_seconds)
        .await
    {
        Err(error) if error.is_io_error() => {
            debug!(%error, cache_key = key, "Redis connection dropped; retrying cache write");
            sleep(Duration::from_millis(75)).await;
            let mut redis = state.redis.clone();
            redis.set_ex::<_, _, ()>(key, value, ttl_seconds).await
        }
        result => result,
    }
}

async fn delete_value(state: &AppState, key: &str) -> RedisResult<()> {
    let mut redis = state.redis.clone();
    match redis.del::<_, ()>(key).await {
        Err(error) if error.is_io_error() => {
            debug!(%error, cache_key = key, "Redis connection dropped; retrying invalidation");
            sleep(Duration::from_millis(75)).await;
            let mut redis = state.redis.clone();
            redis.del::<_, ()>(key).await
        }
        result => result,
    }
}
