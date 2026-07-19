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
const GEOCODING_CACHE_VERSION: &str = "v2";

/// The public Nominatim endpoint permits at most one request per second.
/// Cached coordinate cells keep this development fallback well below that limit.
static NEXT_GEOCODING_REQUEST: LazyLock<Mutex<Instant>> =
    LazyLock::new(|| Mutex::new(Instant::now() - Duration::from_secs(1)));
static WEATHER_CLIENT: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(3))
        .build()
        .unwrap_or_default()
});

#[derive(Debug, Deserialize, IntoParams)]
pub struct CurrentWeatherQuery {
    /// Latitude in WGS84 coordinates.
    pub latitude: f64,
    /// Longitude in WGS84 coordinates.
    pub longitude: f64,
    /// `celsius` or `fahrenheit`.
    pub unit: String,
    /// Supported interface locale. Unsupported values safely fall back to English.
    pub locale: Option<String>,
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

    let response = WEATHER_CLIENT
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

    let geocoding_language = normalize_geocoding_language(query.locale.as_deref());
    let city = resolve_city(&state, query.latitude, query.longitude, geocoding_language).await;

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

async fn resolve_city(
    state: &AppState,
    latitude: f64,
    longitude: f64,
    language: &'static str,
) -> Option<String> {
    // A 0.01° cell is about one kilometre and matches the client's location update threshold.
    // The language and version prevent cached city names from leaking across interface locales.
    let cache_key = city_cache_key(latitude, longitude, language);
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

    let response = WEATHER_CLIENT
        .get(NOMINATIM_REVERSE_URL)
        .query(&[
            ("lat", latitude.to_string()),
            ("lon", longitude.to_string()),
            ("format", "jsonv2".to_owned()),
            ("addressdetails", "1".to_owned()),
        ])
        .header("Accept-Language", language)
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

fn normalize_geocoding_language(locale: Option<&str>) -> &'static str {
    let normalized = locale
        .unwrap_or_default()
        .trim()
        .replace('_', "-")
        .to_ascii_lowercase();

    match normalized.as_str() {
        "ru" | "ru-ru" => "ru",
        "de" | "de-de" | "de-at" | "de-ch" => "de",
        "fr" | "fr-fr" | "fr-ca" | "fr-ch" => "fr",
        "es" | "es-es" | "es-mx" => "es",
        "pt" | "pt-br" => "pt-BR",
        "zh" | "zh-cn" | "zh-hans" => "zh-Hans",
        "en-us" => "en-US",
        _ => "en",
    }
}

fn city_cache_key(latitude: f64, longitude: f64, language: &str) -> String {
    format!("weather:city:{language}:{GEOCODING_CACHE_VERSION}:{latitude:.2}:{longitude:.2}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn geocoding_language_is_limited_to_supported_interface_locales() {
        assert_eq!(normalize_geocoding_language(Some("de-DE")), "de");
        assert_eq!(normalize_geocoding_language(Some("pt_BR")), "pt-BR");
        assert_eq!(normalize_geocoding_language(Some("zh-Hans")), "zh-Hans");
        assert_eq!(
            normalize_geocoding_language(Some("unknown\r\nheader")),
            "en"
        );
        assert_eq!(normalize_geocoding_language(None), "en");
    }

    #[test]
    fn city_cache_is_scoped_to_the_requested_language() {
        assert_eq!(
            city_cache_key(55.7558, 37.6173, "de"),
            "weather:city:de:v2:55.76:37.62"
        );
    }
}
