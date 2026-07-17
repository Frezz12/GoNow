use axum::{
    Json,
    extract::Query,
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use tracing::warn;
use utoipa::{IntoParams, ToSchema};

use crate::shared::{errors::AppError, response::ApiResponse};

const OPEN_METEO_URL: &str = "https://api.open-meteo.com/v1/forecast";

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
    pub temperature: f64,
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
    #[serde(rename = "weather_code")]
    weather_code: i32,
    #[serde(rename = "is_day")]
    is_day: i32,
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
            ("current", "temperature_2m,weather_code,is_day".to_owned()),
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

    let payload = response.json::<OpenMeteoResponse>().await.map_err(|error| {
        warn!(%error, "weather provider response could not be decoded");
        AppError::service_unavailable()
    })?;

    Ok(Json(ApiResponse::new(CurrentWeatherResponse {
        temperature: payload.current.temperature,
        unit: query.unit,
        weather_code: payload.current.weather_code,
        is_day: payload.current.is_day == 1,
    })))
}
