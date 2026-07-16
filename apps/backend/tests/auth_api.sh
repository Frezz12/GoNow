#!/usr/bin/env bash
set -euo pipefail

base_url="${GONOW_INTEGRATION_BASE_URL:-http://127.0.0.1:8080}"
email="integration-$(uuidgen | tr '[:upper:]' '[:lower:]')@example.test"
password="StrongPassword123"
body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

request() {
  local expected_status="$1"
  shift
  local status
  status="$(curl --silent --show-error --output "$body_file" --write-out '%{http_code}' "$@")"
  if [[ "$status" != "$expected_status" ]]; then
    echo "Expected HTTP $expected_status, received $status" >&2
    cat "$body_file" >&2
    exit 1
  fi
}

register_payload="$(jq -cn --arg email "$email" --arg password "$password" '{email:$email,password:$password,displayName:"Integration User",device:{deviceId:"integration-device",deviceName:"CI",platform:"ios"}}')"
request 201 -X POST "$base_url/api/v1/auth/register" -H 'Content-Type: application/json' --data "$register_payload"
access_token="$(jq -r '.data.tokens.accessToken' "$body_file")"
refresh_token="$(jq -r '.data.tokens.refreshToken' "$body_file")"

request 409 -X POST "$base_url/api/v1/auth/register" -H 'Content-Type: application/json' --data "$register_payload"
request 422 -X POST "$base_url/api/v1/auth/register" -H 'Content-Type: application/json' --data '{"email":"wrong","password":"short","displayName":"A","device":{"deviceId":"test","deviceName":"CI","platform":"ios"}}'
request 401 -X POST "$base_url/api/v1/auth/login" -H 'Content-Type: application/json' --data "$(jq -cn --arg email "$email" '{email:$email,password:"wrong-password",device:{deviceId:"integration-device",deviceName:"CI",platform:"ios"}}')"
request 200 -X POST "$base_url/api/v1/auth/login" -H 'Content-Type: application/json' --data "$(jq -cn --arg email "$email" --arg password "$password" '{email:$email,password:$password,device:{deviceId:"integration-device",deviceName:"CI",platform:"ios"}}')"
request 200 "$base_url/api/v1/users/me" -H "Authorization: Bearer $access_token"
request 401 "$base_url/api/v1/users/me"
request 200 -X POST "$base_url/api/v1/auth/refresh" -H 'Content-Type: application/json' --data "$(jq -cn --arg token "$refresh_token" '{refreshToken:$token}')"
new_refresh_token="$(jq -r '.data.tokens.refreshToken' "$body_file")"
request 401 -X POST "$base_url/api/v1/auth/refresh" -H 'Content-Type: application/json' --data "$(jq -cn --arg token "$refresh_token" '{refreshToken:$token}')"
request 200 -X POST "$base_url/api/v1/auth/logout" -H 'Content-Type: application/json' --data "$(jq -cn --arg token "$new_refresh_token" '{refreshToken:$token}')"
request 401 -X POST "$base_url/api/v1/auth/refresh" -H 'Content-Type: application/json' --data "$(jq -cn --arg token "$new_refresh_token" '{refreshToken:$token}')"
request 200 "$base_url/health"

echo "Authentication integration flow passed."
