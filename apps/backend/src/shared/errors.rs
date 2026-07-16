use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use tracing::error;
use uuid::Uuid;

use crate::shared::response::{ErrorBody, ErrorEnvelope};

#[derive(Debug)]
pub struct AppError {
    pub status: StatusCode,
    pub code: &'static str,
    pub message: String,
    pub fields: Option<serde_json::Value>,
}

impl AppError {
    pub fn validation(fields: serde_json::Value) -> Self {
        Self {
            status: StatusCode::UNPROCESSABLE_ENTITY,
            code: "VALIDATION_ERROR",
            message: "Проверьте корректность введённых данных".into(),
            fields: Some(fields),
        }
    }
    pub fn unauthorized(code: &'static str, message: &str) -> Self {
        Self {
            status: StatusCode::UNAUTHORIZED,
            code,
            message: message.into(),
            fields: None,
        }
    }
    pub fn service_unavailable() -> Self {
        Self {
            status: StatusCode::SERVICE_UNAVAILABLE,
            code: "SERVICE_UNAVAILABLE",
            message: "Сервис временно недоступен. Повторите попытку позже".into(),
            fields: None,
        }
    }
    pub fn internal(error: impl std::fmt::Display) -> Self {
        error!(error = %error, "unhandled application error");
        Self {
            status: StatusCode::INTERNAL_SERVER_ERROR,
            code: "INTERNAL_ERROR",
            message: "Внутренняя ошибка сервиса".into(),
            fields: None,
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let request_id = Uuid::new_v4().to_string();
        let body = ErrorEnvelope {
            error: ErrorBody {
                code: self.code.into(),
                message: self.message,
                fields: self.fields,
                request_id: request_id.clone(),
            },
        };
        let mut response = (self.status, Json(body)).into_response();
        if let Ok(value) = request_id.parse() {
            response.headers_mut().insert("x-request-id", value);
        }
        response
    }
}
