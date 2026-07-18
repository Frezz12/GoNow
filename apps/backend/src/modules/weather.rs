use std::{
    sync::{LazyLock, Mutex},
    time::{Duration, Instant},
};

use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use tracing::warn;
use utoipa::{IntoParams, ToSchema};

use crate::{
    app::AppState,
    shared::{errors::AppError, response::ApiResponse},
};

const OPEN_METEO_URL: &str = "https://api.open-meteo.com/v1/forecast";
const NOMINATIM_REVERSE_URL: &str = "https://nominatim.openstreetmap.org/reverse";
const GEOCODING_CACHE_TTL_SECONDS: u64 = 60 * 60 * 24;

/// The public Nominatim endpoint permits at most one request per second.
/// Cached coordinate cells keep this development fallback well below that limit.
static NEXT_GEOCODING_REQUEST: LazyLock<Mutex<Instant>> =
    LazyLock::new(|| Mutex::new(Instant::now() - Duration::from_secs(1)));

#[derive(Debug, Deserialize, IntoParams)]
pub struct CurrentWeatherQuery {
    /// Latitude in WGS84 coordinates.
    pub latitude: f64,
    /// Longitude in WGS84 coordinates.
    pub longitude: f64,
    /// `celsius` or `fahrenheit`.
    pub unit: String,
}

#[derive(Debug, Serialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CurrentWeatherResponse {
    /// The city resolved for the same coordinates as the weather data.
    pub city: Option<String>,
    pub temperature: f64,
    pub apparent_temperature: f64,
    pub relative_humidity: f64,
    pub wind_speed: f64,
    pub unit: String,
    pub weather_code: i32,
    pub is_day: bool,
}

#[derive(Debug, Deserialize)]
struct OpenMeteoResponse {
    current: OpenMeteoCurrent,
}

#[derive(Debug, Deserialize)]
struct OpenMeteoCurrent {
    #[serde(rename = "temperature_2m")]
    temperature: f64,
    #[serde(rename = "apparent_temperature")]
    apparent_temperature: f64,
    #[serde(rename = "relative_humidity_2m")]
    relative_humidity: f64,
    #[serde(rename = "wind_speed_10m")]
    wind_speed: f64,
    #[serde(rename = "weather_code")]
    weather_code: i32,
    #[serde(rename = "is_day")]
    is_day: i32,
}

#[derive(Debug, Deserialize)]
struct NominatimReverseResponse {
    address: NominatimAddress,
}

#[derive(Debug, Deserialize)]
struct NominatimAddress {
    city: Option<String>,
    town: Option<String>,
    village: Option<String>,
    municipality: Option<String>,
    county: Option<String>,
}

impl NominatimAddress {
    fn locality(self) -> Option<String> {
        self.city
            .or(self.town)
            .or(self.village)
            .or(self.municipality)
            .or(self.county)
    }
}

#[utoipa::path(
    get,
    path = "/api/v1/weather/current",
    tag = "weather",
    params(CurrentWeatherQuery),
    responses(
        (status = 200, body = CurrentWeatherResponse),
        (status = 422, description = "Invalid coordinates or unit"),
        (status = 503, description = "Weather provider is unavailable")
    )
)]
pub async fn current(
    State(state): State<AppState>,
    Query(query): Query<CurrentWeatherQuery>,
) -> Result<Json<ApiResponse<CurrentWeatherResponse>>, AppError> {
    if !(-90.0..=90.0).contains(&query.latitude)
        || !(-180.0..=180.0).contains(&query.longitude)
        || !matches!(query.unit.as_str(), "celsius" | "fahrenheit")
    {
        return Err(AppError::validation(serde_json::json!({
            "weather": "Передайте координаты и единицу температуры: celsius или fahrenheit"
        })));
    }

    let response = reqwest::Client::new()
        .get(OPEN_METEO_URL)
        .query(&[
            ("latitude", query.latitude.to_string()),
            ("longitude", query.longitude.to_string()),
            ("current", "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day".to_owned()),
            ("temperature_unit", query.unit.clone()),
            ("forecast_days", "1".to_owned()),
        ])
        .timeout(std::time::Duration::from_secs(12))
        .send()
        .await
        .map_err(|error| {
            warn!(%error, "weather provider request failed");
            AppError::service_unavailable()
        })?;

    if response.status() != StatusCode::OK {
        warn!(status = %response.status(), "weather provider returned an unsuccessful status");
        return Err(AppError::service_unavailable());
    }

    let payload = response
        .json::<OpenMeteoResponse>()
        .await
        .map_err(|error| {
            warn!(%error, "weather provider response could not be decoded");
            AppError::service_unavailable()
        })?;

    let city = resolve_city(&state, query.latitude, query.longitude).await;

    Ok(Json(ApiResponse::new(CurrentWeatherResponse {
        city,
        temperature: payload.current.temperature,
        apparent_temperature: payload.current.apparent_temperature,
        relative_humidity: payload.current.relative_humidity,
        wind_speed: payload.current.wind_speed,
        unit: query.unit,
        weather_code: payload.current.weather_code,
        is_day: payload.current.is_day == 1,
    })))
}

async fn resolve_city(state: &AppState, latitude: f64, longitude: f64) -> Option<String> {
    // A 0.01° cell is about one kilometre and matches the client's location update threshold.
    let cache_key = format!("weather:city:{latitude:.2}:{longitude:.2}");
    let mut redis = state.redis.clone();
    if let Ok(Some(city)) = redis.get::<_, Option<String>>(&cache_key).await {
        return Some(city);
    }

    let delay = match NEXT_GEOCODING_REQUEST.lock() {
        Ok(mut next_allowed) => {
            let now = Instant::now();
            let delay = next_allowed.saturating_duration_since(now);
            *next_allowed = now + delay + Duration::from_secs(1);
            delay
        }
        Err(error) => {
            warn!(%error, "city reverse geocoding limiter is unavailable");
            return None;
        }
    };
    if !delay.is_zero() {
        tokio::time::sleep(delay).await;
    }

    let response = reqwest::Client::new()
        .get(NOMINATIM_REVERSE_URL)
        .query(&[
            ("lat", latitude.to_string()),
            ("lon", longitude.to_string()),
            ("format", "jsonv2".to_owned()),
            ("addressdetails", "1".to_owned()),
        ])
        .header("Accept-Language", "ru,en")
        .header(
            "User-Agent",
            "GoNow/0.1 (+https://github.com/Frezz12/GoNow)",
        )
        .timeout(Duration::from_secs(4))
        .send()
        .await
        .map_err(|error| warn!(%error, "city reverse geocoding request failed"))
        .ok()?;

    if response.status() != StatusCode::OK {
        warn!(status = %response.status(), "city reverse geocoding returned an unsuccessful status");
        return None;
    }

    let city = response
        .json::<NominatimReverseResponse>()
        .await
        .map_err(|error| warn!(%error, "city reverse geocoding response could not be decoded"))
        .ok()?
        .address
        .locality()?;

    let mut redis = state.redis.clone();
    if let Err(error) = redis
        .set_ex::<_, _, ()>(&cache_key, &city, GEOCODING_CACHE_TTL_SECONDS)
        .await
    {
        warn!(%error, "city reverse geocoding cache write failed");
    }
    Some(city)
}
