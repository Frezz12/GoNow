use std::{
    net::{IpAddr, SocketAddr},
    sync::{LazyLock, RwLock},
    time::Duration,
};

use axum::{
    Json,
    body::Body,
    extract::{OriginalUri, Path, State},
    http::{HeaderMap, HeaderName, StatusCode, uri::Authority},
    response::{IntoResponse, Response},
};
use serde::Deserialize;
use serde_json::{Value, json};
use tracing::warn;

use crate::{app::AppState, shared::errors::AppError};

const OPEN_FREE_MAP_ORIGIN: &str = "https://tiles.openfreemap.org";
const OPEN_FREE_MAP_HOST: &str = "tiles.openfreemap.org";
const CLOUDFLARE_DOH_HOST: &str = "cloudflare-dns.com";
const CLOUDFLARE_DOH_URL: &str = "https://cloudflare-dns.com/dns-query";
const RESOURCE_ROUTE_PREFIX: &str = "/api/v1/map/resources/";
const UPSTREAM_TIMEOUT: Duration = Duration::from_secs(12);
const UPSTREAM_CONNECT_TIMEOUT: Duration = Duration::from_secs(3);
static MAP_CLIENT: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .timeout(UPSTREAM_TIMEOUT)
        .connect_timeout(UPSTREAM_CONNECT_TIMEOUT)
        .user_agent("GoNow/0.1 (+https://github.com/Frezz12/GoNow)")
        .build()
        .unwrap_or_default()
});
static DOH_CLIENT: LazyLock<reqwest::Client> = LazyLock::new(|| {
    let addresses = [
        SocketAddr::from(([1, 1, 1, 1], 443)),
        SocketAddr::from(([1, 0, 0, 1], 443)),
    ];
    reqwest::Client::builder()
        .timeout(UPSTREAM_TIMEOUT)
        .connect_timeout(UPSTREAM_CONNECT_TIMEOUT)
        .user_agent("GoNow/0.1 (+https://github.com/Frezz12/GoNow)")
        .resolve_to_addrs(CLOUDFLARE_DOH_HOST, &addresses)
        .build()
        .unwrap_or_default()
});
static DOH_RESOLVED_MAP_CLIENT: LazyLock<RwLock<Option<reqwest::Client>>> =
    LazyLock::new(|| RwLock::new(None));

#[derive(Debug, Deserialize)]
struct DnsOverHttpsResponse {
    #[serde(rename = "Status")]
    status: u16,
    #[serde(rename = "Answer", default)]
    answers: Vec<DnsOverHttpsAnswer>,
}

#[derive(Debug, Deserialize)]
struct DnsOverHttpsAnswer {
    #[serde(rename = "type")]
    record_type: u16,
    data: String,
}

/// Returns the OpenFreeMap Liberty style with every provider URL routed through GoNow.
/// If OpenFreeMap DNS is temporarily unavailable, a lightweight OSM raster style keeps
/// the map and GoNow activity markers usable instead of leaving clients on a spinner.
pub async fn style(State(_state): State<AppState>, headers: HeaderMap) -> Response {
    let map_base_url = map_base_url(&headers);
    match ready_vector_style(&map_base_url).await {
        Ok(style) => json_response(style, "public, max-age=300"),
        Err(error) => {
            warn!(
                error_code = error.code,
                "OpenFreeMap style unavailable; serving OSM raster fallback"
            );
            json_response(fallback_style(), "no-store")
        }
    }
}

async fn ready_vector_style(map_base_url: &str) -> Result<Value, AppError> {
    let mut style = fetch_json("/styles/liberty").await?;
    let mut tile_json = fetch_json("/planet").await?;
    tune_style_for_gonow(&mut style);
    rewrite_tile_json_urls(&mut tile_json, map_base_url);
    inline_vector_source(&mut style, &tile_json)?;
    rewrite_style_urls(&mut style, map_base_url);
    Ok(style)
}

/// TileJSON is kept as a separate route because its tile templates must also point
/// back to GoNow rather than exposing the provider hostname to the mobile client.
pub async fn planet(
    State(_state): State<AppState>,
    headers: HeaderMap,
) -> Result<Response, AppError> {
    let map_base_url = map_base_url(&headers);
    let mut tile_json = fetch_json("/planet").await?;
    rewrite_tile_json_urls(&mut tile_json, &map_base_url);
    Ok(json_response(tile_json, "public, max-age=300"))
}

/// Relays only the four resource trees referenced by the official OpenFreeMap style.
/// The allow-list prevents this endpoint from becoming a general-purpose open proxy.
pub async fn resource(
    State(_state): State<AppState>,
    Path(decoded_path): Path<String>,
    OriginalUri(original_uri): OriginalUri,
) -> Result<Response, AppError> {
    if !is_allowed_resource_path(&decoded_path) {
        return Ok(StatusCode::NOT_FOUND.into_response());
    }

    let raw_path = original_uri
        .path()
        .strip_prefix(RESOURCE_ROUTE_PREFIX)
        .filter(|path| !path.is_empty())
        .ok_or_else(AppError::service_unavailable)?;
    proxy_resource(raw_path).await
}

async fn fetch_json(path: &str) -> Result<Value, AppError> {
    let response = send_provider_request(path).await?;

    if !response.status().is_success() {
        warn!(status = %response.status(), upstream_path = path, "map provider returned an unsuccessful status");
        return Err(AppError::service_unavailable());
    }

    response.json::<Value>().await.map_err(|error| {
        warn!(%error, upstream_path = path, "map provider JSON could not be decoded");
        AppError::service_unavailable()
    })
}

async fn proxy_resource(raw_path: &str) -> Result<Response, AppError> {
    let response = send_provider_request(&format!("/{raw_path}")).await?;
    let status = response.status();
    let upstream_headers = response.headers().clone();
    let bytes = response.bytes().await.map_err(|error| {
        warn!(%error, upstream_path = raw_path, "map resource body could not be read");
        AppError::service_unavailable()
    })?;

    let mut builder = Response::builder().status(status);
    for name in [
        axum::http::header::CONTENT_TYPE,
        axum::http::header::CONTENT_ENCODING,
        axum::http::header::CACHE_CONTROL,
        axum::http::header::ETAG,
        axum::http::header::LAST_MODIFIED,
    ] {
        if let Some(value) = upstream_headers.get(&name) {
            builder = builder.header(name, value);
        }
    }
    if !upstream_headers.contains_key(axum::http::header::CACHE_CONTROL) {
        builder = builder.header(axum::http::header::CACHE_CONTROL, "public, max-age=86400");
    }
    builder.body(Body::from(bytes)).map_err(AppError::internal)
}

async fn send_provider_request(path: &str) -> Result<reqwest::Response, AppError> {
    let url = format!("{OPEN_FREE_MAP_ORIGIN}{path}");

    // Once the system resolver has failed, keep using the verified DoH client for
    // subsequent sprites, glyphs and tiles. Retrying broken VPN DNS for every tile
    // made uncached regions appear to load in slow, incomplete waves.
    if let Some(fallback_client) = cached_doh_map_client() {
        match fallback_client.get(&url).send().await {
            Ok(response) => return Ok(response),
            Err(error) => {
                warn!(%error, upstream_path = path, "cached map DNS-over-HTTPS connection failed; resolving again");
                clear_cached_doh_map_client();
            }
        }
    }

    match MAP_CLIENT.get(&url).send().await {
        Ok(response) => Ok(response),
        Err(primary_error) => {
            warn!(%primary_error, upstream_path = path, "map provider request failed; retrying with DNS-over-HTTPS");
            let fallback_client = dns_over_https_map_client().await?;
            fallback_client.get(url).send().await.map_err(|fallback_error| {
                warn!(%fallback_error, upstream_path = path, "map provider DNS-over-HTTPS retry failed");
                AppError::service_unavailable()
            })
        }
    }
}

async fn dns_over_https_map_client() -> Result<reqwest::Client, AppError> {
    if let Ok(guard) = DOH_RESOLVED_MAP_CLIENT.read()
        && let Some(client) = guard.as_ref()
    {
        return Ok(client.clone());
    }

    let response = DOH_CLIENT
        .get(CLOUDFLARE_DOH_URL)
        .query(&[("name", OPEN_FREE_MAP_HOST), ("type", "A")])
        .header(reqwest::header::ACCEPT, "application/dns-json")
        .send()
        .await
        .map_err(|error| {
            warn!(%error, "map provider DNS-over-HTTPS lookup failed");
            AppError::service_unavailable()
        })?;
    if !response.status().is_success() {
        warn!(status = %response.status(), "map provider DNS-over-HTTPS returned an unsuccessful status");
        return Err(AppError::service_unavailable());
    }

    let payload = response
        .json::<DnsOverHttpsResponse>()
        .await
        .map_err(|error| {
            warn!(%error, "map provider DNS-over-HTTPS response could not be decoded");
            AppError::service_unavailable()
        })?;
    let addresses = dns_socket_addresses(&payload);
    if payload.status != 0 || addresses.is_empty() {
        warn!(
            dns_status = payload.status,
            "map provider DNS-over-HTTPS returned no IPv4 addresses"
        );
        return Err(AppError::service_unavailable());
    }

    let client = reqwest::Client::builder()
        .timeout(UPSTREAM_TIMEOUT)
        .connect_timeout(UPSTREAM_CONNECT_TIMEOUT)
        .user_agent("GoNow/0.1 (+https://github.com/Frezz12/GoNow)")
        .resolve_to_addrs(OPEN_FREE_MAP_HOST, &addresses)
        .build()
        .map_err(AppError::internal)?;
    if let Ok(mut guard) = DOH_RESOLVED_MAP_CLIENT.write() {
        *guard = Some(client.clone());
    }
    Ok(client)
}

fn cached_doh_map_client() -> Option<reqwest::Client> {
    DOH_RESOLVED_MAP_CLIENT
        .read()
        .ok()
        .and_then(|guard| guard.as_ref().cloned())
}

fn clear_cached_doh_map_client() {
    if let Ok(mut guard) = DOH_RESOLVED_MAP_CLIENT.write() {
        *guard = None;
    }
}

fn dns_socket_addresses(payload: &DnsOverHttpsResponse) -> Vec<SocketAddr> {
    payload
        .answers
        .iter()
        .filter(|answer| answer.record_type == 1)
        .filter_map(|answer| answer.data.parse::<IpAddr>().ok())
        .map(|ip| SocketAddr::new(ip, 443))
        .collect()
}

fn inline_vector_source(style: &mut Value, tile_json: &Value) -> Result<(), AppError> {
    let source = style
        .get_mut("sources")
        .and_then(Value::as_object_mut)
        .and_then(|sources| sources.get_mut("openmaptiles"))
        .and_then(Value::as_object_mut)
        .ok_or_else(AppError::service_unavailable)?;
    let tiles = tile_json
        .get("tiles")
        .and_then(Value::as_array)
        .filter(|tiles| !tiles.is_empty())
        .cloned()
        .ok_or_else(AppError::service_unavailable)?;

    source.remove("url");
    source.insert("tiles".to_owned(), Value::Array(tiles));
    for field in ["minzoom", "maxzoom", "bounds", "scheme", "attribution"] {
        if let Some(value) = tile_json.get(field) {
            source.insert(field.to_owned(), value.clone());
        }
    }
    Ok(())
}

/// Makes the worldwide Liberty style more useful for activity discovery.
///
/// Russian settlements are frequently classified as towns or villages rather than
/// cities, and the upstream style delays those labels. It also renders non-Latin
/// names on two lines, which causes substantially more label collisions over Russia.
/// GoNow shows one native label and brings settlement/road detail forward modestly.
fn tune_style_for_gonow(style: &mut Value) {
    let Some(layers) = style.get_mut("layers").and_then(Value::as_array_mut) else {
        return;
    };

    for layer in layers {
        let Some(identifier) = layer.get("id").and_then(Value::as_str).map(str::to_owned) else {
            continue;
        };

        let minimum_zoom = match identifier.as_str() {
            "label_town" => Some(4.5),
            "label_village" => Some(7.0),
            "label_other" => Some(7.0),
            "highway-name-major" => Some(10.5),
            "highway-name-minor" => Some(13.5),
            "highway-name-path" => Some(14.5),
            _ => None,
        };
        if let Some(minimum_zoom) = minimum_zoom
            && let Some(object) = layer.as_object_mut()
        {
            object.insert("minzoom".to_owned(), json!(minimum_zoom));
        }

        let source_layer = layer.get("source-layer").and_then(Value::as_str);
        if matches!(source_layer, Some("place" | "transportation_name"))
            && let Some(layout) = layer.get_mut("layout").and_then(Value::as_object_mut)
            && layout.contains_key("text-field")
        {
            layout.insert(
                "text-field".to_owned(),
                json!([
                    "coalesce",
                    ["get", "name"],
                    ["get", "name:nonlatin"],
                    ["get", "name_en"],
                    ["get", "name:latin"]
                ]),
            );
        }

        if matches!(
            identifier.as_str(),
            "label_city" | "label_city_capital" | "label_town" | "label_village"
        ) && let Some(layout) = layer.get_mut("layout").and_then(Value::as_object_mut)
        {
            // Lower rank means a more important settlement in OpenMapTiles. Without
            // an explicit sort key MapLibre may prioritize labels by viewport Y,
            // which hides many important Russian cities in dense tiles.
            layout.insert(
                "symbol-sort-key".to_owned(),
                json!(["coalesce", ["get", "rank"], 99]),
            );
            layout.insert(
                "text-variable-anchor".to_owned(),
                json!(["bottom", "top", "left", "right"]),
            );
            layout.insert("text-justify".to_owned(), json!("auto"));
            layout.insert("text-radial-offset".to_owned(), json!(0.35));
            layout.insert("text-padding".to_owned(), json!(1));
            layout.remove("text-anchor");
            layout.remove("text-offset");
        }

        if identifier == "label_state" {
            if let Some(object) = layer.as_object_mut() {
                object.insert("maxzoom".to_owned(), json!(6.0));
            }
            if let Some(layout) = layer.get_mut("layout").and_then(Value::as_object_mut) {
                layout.insert("text-ignore-placement".to_owned(), json!(true));
            }
        }

        if identifier.starts_with("label_country_")
            && let Some(layout) = layer.get_mut("layout").and_then(Value::as_object_mut)
        {
            // Country labels provide context at overview zooms but must not reserve
            // collision space that prevents nearby city labels from appearing.
            layout.insert("text-ignore-placement".to_owned(), json!(true));
        }

        if matches!(identifier.as_str(), "label_town" | "label_village")
            && let Some(layout) = layer.get_mut("layout").and_then(Value::as_object_mut)
        {
            // These layers are placed before city layers in Liberty. They remain
            // visible but no longer suppress higher-priority city names.
            layout.insert("text-ignore-placement".to_owned(), json!(true));
        }

        let road_detail_shift = match identifier.as_str() {
            "road_minor"
            | "road_minor_casing"
            | "road_service_track"
            | "road_service_track_casing" => Some(1.5),
            "road_secondary_tertiary"
            | "road_secondary_tertiary_casing"
            | "road_trunk_primary"
            | "road_trunk_primary_casing" => Some(1.0),
            _ => None,
        };
        if let Some(shift) = road_detail_shift
            && let Some(width) = layer.pointer_mut("/paint/line-width")
        {
            shift_interpolated_zoom_stops(width, shift);
        }
    }
}

fn shift_interpolated_zoom_stops(expression: &mut Value, shift: f64) {
    let Some(parts) = expression.as_array_mut() else {
        return;
    };
    let is_zoom_interpolation = parts.first().and_then(Value::as_str) == Some("interpolate")
        && parts
            .get(2)
            .and_then(Value::as_array)
            .and_then(|input| input.first())
            .and_then(Value::as_str)
            == Some("zoom");
    if !is_zoom_interpolation {
        return;
    }

    for index in (3..parts.len()).step_by(2) {
        if let Some(zoom) = parts[index].as_f64() {
            parts[index] = json!((zoom - shift).max(0.0));
        }
    }
}

fn rewrite_style_urls(style: &mut Value, map_base_url: &str) {
    if let Some(sources) = style.get_mut("sources").and_then(Value::as_object_mut) {
        for source in sources.values_mut() {
            if let Some(url) = source.get_mut("url") {
                if url.as_str() == Some(&format!("{OPEN_FREE_MAP_ORIGIN}/planet")) {
                    *url = Value::String(format!("{map_base_url}/planet"));
                } else if let Some(rewritten) = url
                    .as_str()
                    .and_then(|value| rewrite_provider_url(value, map_base_url))
                {
                    *url = Value::String(rewritten);
                }
            }
            if let Some(tiles) = source.get_mut("tiles").and_then(Value::as_array_mut) {
                rewrite_url_array(tiles, map_base_url);
            }
        }
    }

    for field in ["sprite", "glyphs"] {
        if let Some(value) = style.get_mut(field)
            && let Some(rewritten) = value
                .as_str()
                .and_then(|url| rewrite_provider_url(url, map_base_url))
        {
            *value = Value::String(rewritten);
        }
    }
}

fn rewrite_tile_json_urls(tile_json: &mut Value, map_base_url: &str) {
    if let Some(tiles) = tile_json.get_mut("tiles").and_then(Value::as_array_mut) {
        rewrite_url_array(tiles, map_base_url);
    }
}

fn rewrite_url_array(urls: &mut [Value], map_base_url: &str) {
    for value in urls {
        if let Some(rewritten) = value
            .as_str()
            .and_then(|url| rewrite_provider_url(url, map_base_url))
        {
            *value = Value::String(rewritten);
        }
    }
}

fn rewrite_provider_url(url: &str, map_base_url: &str) -> Option<String> {
    url.strip_prefix(&format!("{OPEN_FREE_MAP_ORIGIN}/"))
        .map(|path| format!("{map_base_url}/resources/{path}"))
}

fn is_allowed_resource_path(path: &str) -> bool {
    !path.is_empty()
        && !path.contains("..")
        && !path.contains('\\')
        && ["natural_earth/", "planet/", "sprites/", "fonts/"]
            .iter()
            .any(|prefix| path.starts_with(prefix))
}

fn map_base_url(headers: &HeaderMap) -> String {
    let forwarded_proto = header_string(headers, "x-forwarded-proto");
    let host = header_string(headers, "x-forwarded-host")
        .or_else(|| header_string(headers, "host"))
        .and_then(|value| {
            value
                .parse::<Authority>()
                .ok()
                .map(|authority| authority.to_string())
        })
        .unwrap_or_else(|| "127.0.0.1:8080".to_owned());
    let scheme = match forwarded_proto.as_deref() {
        Some("http") if is_local_host(&host) => "http",
        Some("https") => "https",
        _ if is_local_host(&host) => "http",
        _ => "https",
    };
    format!("{scheme}://{host}/api/v1/map")
}

fn header_string(headers: &HeaderMap, name: &'static str) -> Option<String> {
    headers
        .get(HeaderName::from_static(name))
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.split(',').next())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

fn is_local_host(host: &str) -> bool {
    let Ok(authority) = host.parse::<Authority>() else {
        return false;
    };
    let hostname = authority.host().trim_matches(['[', ']']);
    if hostname.eq_ignore_ascii_case("localhost") {
        return true;
    }
    hostname
        .parse::<IpAddr>()
        .is_ok_and(|address| match address {
            IpAddr::V4(address) => address.is_loopback() || address.is_private(),
            IpAddr::V6(address) => address.is_loopback(),
        })
}

fn fallback_style() -> Value {
    json!({
        "version": 8,
        "name": "GoNow OpenStreetMap fallback",
        "sources": {
            "openstreetmap": {
                "type": "raster",
                "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
                "tileSize": 256,
                "minzoom": 0,
                "maxzoom": 19,
                "attribution": "© OpenStreetMap contributors"
            }
        },
        "layers": [
            { "id": "background", "type": "background", "paint": { "background-color": "#F6F2F5" } },
            { "id": "openstreetmap", "type": "raster", "source": "openstreetmap", "minzoom": 0, "maxzoom": 19 }
        ]
    })
}

fn json_response(value: Value, cache_control: &'static str) -> Response {
    let mut response = Json(value).into_response();
    response.headers_mut().insert(
        axum::http::header::CACHE_CONTROL,
        cache_control
            .parse()
            .expect("static cache-control header is valid"),
    );
    response
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rewrites_every_provider_url_in_style() {
        let mut style = json!({
            "sources": {
                "openmaptiles": { "type": "vector", "url": "https://tiles.openfreemap.org/planet" },
                "raster": { "tiles": ["https://tiles.openfreemap.org/natural_earth/ne2sr/{z}/{x}/{y}.png"] }
            },
            "sprite": "https://tiles.openfreemap.org/sprites/ofm_f384/ofm",
            "glyphs": "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"
        });
        let mut tile_json = json!({
            "tiles": ["https://tiles.openfreemap.org/planet/20260621_080001_pt/{z}/{x}/{y}.pbf"],
            "minzoom": 0,
            "maxzoom": 14
        });

        let map_base = "https://api.gonow.example/api/v1/map";
        rewrite_tile_json_urls(&mut tile_json, map_base);
        inline_vector_source(&mut style, &tile_json).unwrap();
        rewrite_style_urls(&mut style, map_base);

        let serialized = style.to_string();
        assert!(!serialized.contains("tiles.openfreemap.org"));
        assert!(!serialized.contains("\"url\""));
        assert!(serialized.contains("/api/v1/map/resources/planet/"));
        assert!(serialized.contains("/api/v1/map/resources/fonts/"));
    }

    #[test]
    fn rejects_paths_outside_the_provider_allow_list() {
        assert!(is_allowed_resource_path("planet/latest/10/1/2.pbf"));
        assert!(is_allowed_resource_path("fonts/Noto%20Sans/0-255.pbf"));
        assert!(!is_allowed_resource_path("../styles/liberty"));
        assert!(!is_allowed_resource_path("https://example.com/file"));
    }

    #[test]
    fn map_base_url_rejects_untrusted_schemes_and_malformed_hosts() {
        let mut headers = HeaderMap::new();
        headers.insert("host", "api.gonow.example".parse().unwrap());
        headers.insert("x-forwarded-proto", "javascript".parse().unwrap());
        assert_eq!(
            map_base_url(&headers),
            "https://api.gonow.example/api/v1/map"
        );

        headers.insert("host", "10.evil.example".parse().unwrap());
        headers.insert("x-forwarded-proto", "http".parse().unwrap());
        assert_eq!(map_base_url(&headers), "https://10.evil.example/api/v1/map");
    }

    #[test]
    fn keeps_only_ipv4_answers_from_dns_over_https() {
        let payload: DnsOverHttpsResponse = serde_json::from_value(json!({
            "Status": 0,
            "Answer": [
                { "type": 5, "data": "edge.example.org" },
                { "type": 1, "data": "104.26.7.23" },
                { "type": 28, "data": "2606:4700::681a:717" }
            ]
        }))
        .unwrap();

        assert_eq!(
            dns_socket_addresses(&payload),
            vec!["104.26.7.23:443".parse::<SocketAddr>().unwrap()]
        );
    }

    #[test]
    fn tunes_native_settlement_labels_and_earlier_road_detail() {
        let mut style = json!({
            "layers": [
                {
                    "id": "label_town",
                    "type": "symbol",
                    "source-layer": "place",
                    "minzoom": 6,
                    "layout": { "text-field": ["concat", ["get", "name:latin"], ["get", "name:nonlatin"]] }
                },
                {
                    "id": "road_minor",
                    "type": "line",
                    "source-layer": "transportation",
                    "paint": { "line-width": ["interpolate", ["linear"], ["zoom"], 13.5, 0, 14, 2.5, 20, 18] }
                },
                {
                    "id": "label_state",
                    "type": "symbol",
                    "source-layer": "place",
                    "minzoom": 5,
                    "maxzoom": 8,
                    "layout": { "text-field": ["get", "name"] }
                }
            ]
        });

        tune_style_for_gonow(&mut style);

        assert_eq!(style.pointer("/layers/0/minzoom"), Some(&json!(4.5)));
        assert_eq!(
            style.pointer("/layers/0/layout/text-field"),
            Some(&json!([
                "coalesce",
                ["get", "name"],
                ["get", "name:nonlatin"],
                ["get", "name_en"],
                ["get", "name:latin"]
            ]))
        );
        assert_eq!(
            style.pointer("/layers/0/layout/symbol-sort-key"),
            Some(&json!(["coalesce", ["get", "rank"], 99]))
        );
        assert_eq!(
            style.pointer("/layers/0/layout/text-variable-anchor"),
            Some(&json!(["bottom", "top", "left", "right"]))
        );
        assert_eq!(
            style.pointer("/layers/0/layout/text-ignore-placement"),
            Some(&json!(true))
        );
        assert_eq!(
            style.pointer("/layers/1/paint/line-width/3"),
            Some(&json!(12.0))
        );
        assert_eq!(
            style.pointer("/layers/1/paint/line-width/5"),
            Some(&json!(12.5))
        );
        assert_eq!(style.pointer("/layers/2/maxzoom"), Some(&json!(6.0)));
        assert_eq!(
            style.pointer("/layers/2/layout/text-ignore-placement"),
            Some(&json!(true))
        );
    }

    #[tokio::test]
    #[ignore = "requires access to the public OpenFreeMap service"]
    async fn provider_request_can_load_tile_json_with_dns_fallback() {
        let _ = tracing_subscriber::fmt()
            .with_env_filter("gonow_backend=debug")
            .try_init();
        let response = send_provider_request("/planet").await.unwrap();
        assert!(response.status().is_success());
        let payload = response.json::<Value>().await.unwrap();
        assert!(
            payload
                .get("tiles")
                .and_then(Value::as_array)
                .is_some_and(|tiles| !tiles.is_empty())
        );
    }

    #[tokio::test]
    #[ignore = "requires access to the public OpenFreeMap service"]
    async fn provider_can_build_a_complete_proxied_style() {
        let map_base = "https://api.gonow.example/api/v1/map";
        let style = ready_vector_style(map_base).await.unwrap();
        let serialized = style.to_string();

        assert_eq!(style.get("version"), Some(&json!(8)));
        assert!(serialized.contains("https://api.gonow.example/api/v1/map/resources/planet/"));
        assert!(serialized.contains("https://api.gonow.example/api/v1/map/resources/fonts/"));
        assert!(!serialized.contains(OPEN_FREE_MAP_ORIGIN));
    }
}
