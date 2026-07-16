mod app;
mod config;
mod infrastructure;
mod modules;
mod shared;

use std::net::SocketAddr;

use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> Result<(), String> {
    dotenvy::dotenv().ok();
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .with(
            tracing_subscriber::fmt::layer()
                .compact()
                .with_target(false),
        )
        .init();

    let config = config::Config::from_environment()?;
    let state = app::AppState::connect(config.clone()).await?;
    let app = app::router(state);
    let address: SocketAddr = format!("{}:{}", config.host, config.port)
        .parse()
        .map_err(|_| "invalid APP_HOST or APP_PORT".to_string())?;
    let listener = tokio::net::TcpListener::bind(address)
        .await
        .map_err(|error| format!("unable to bind listener: {error}"))?;
    info!(%address, environment = %config.app_env, "GoNow API listening");
    axum::serve(listener, app)
        .await
        .map_err(|error| format!("HTTP server failed: {error}"))
}
