import type { ApiResponse, User, Device } from '~/utils/types'
import { ApiError } from '~/utils/api-error'
import {
  getStoredTokens,
  saveTokens,
  saveUser,
  clearSession,
} from '~/utils/auth-storage'

function headers(auth = false): Record<string, string> {
  const h: Record<string, string> = { 'Content-Type': 'application/json' }
  if (auth) {
    const { accessToken } = getStoredTokens()
    if (accessToken) h['Authorization'] = `Bearer ${accessToken}`
  }
  return h
}

async function refreshTokens(): Promise<boolean> {
  const { refreshToken } = getStoredTokens()
  if (!refreshToken) return false
  const config = useRuntimeConfig()
  try {
      const res = await fetch(`${config.public.backendBase}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken }),
    })
    if (!res.ok) return false
    const json = await res.json()
    saveTokens(
      json.data.tokens.accessToken,
      json.data.tokens.refreshToken,
      json.data.tokens.accessTokenExpiresAt,
    )
    return true
  } catch {
    return false
  }
}

async function request<T>(
  method: string,
  path: string,
  body?: unknown,
  auth = false,
): Promise<T> {
  const config = useRuntimeConfig()
  let res = await fetch(`${config.public.backendBase}${path}`, {
    method,
    headers: headers(auth),
    body: body ? JSON.stringify(body) : undefined,
  })

  if (res.status === 401 && auth) {
    const refreshed = await refreshTokens()
    if (refreshed) {
      res = await fetch(`${config.public.backendBase}${path}`, {
        method,
        headers: headers(true),
        body: body ? JSON.stringify(body) : undefined,
      })
    } else {
      clearSession()
      navigateTo('/login')
      throw new ApiError(401, {
        code: 'UNAUTHORIZED',
        message: 'Session expired',
        requestId: '',
      })
    }
  }

  if (!res.ok) {
    let errorBody: { error: ApiErrorBody } | null = null
    try {
      errorBody = await res.json()
    } catch { /* ignore */ }
    if (errorBody?.error) throw new ApiError(res.status, errorBody.error)
    throw new ApiError(res.status, {
      code: 'UNKNOWN_ERROR',
      message: `HTTP ${res.status}`,
      requestId: '',
    })
  }

  if (res.status === 204) return undefined as T
  return (await res.json()) as T
}

interface ApiErrorBody {
  code: string
  message: string
  fields?: Record<string, string>
  requestId: string
}

/* ---- Auth API ---- */

export function authApi() {
  return {
    register(data: { email: string; password: string; displayName: string; username: string; device: Device }) {
      return request<ApiResponse<{ email: string; verificationRequired: boolean; expiresAt: string }>>(
        'POST', '/auth/register', data,
      )
    },
    verifyEmail(data: { email: string; code: string; device: Device }) {
      return request<ApiResponse<{ user: User; tokens: { accessToken: string; refreshToken: string; accessTokenExpiresAt: string } }>>(
        'POST', '/auth/verify-email', data,
      )
    },
    login(data: { email: string; password: string; device: Device }) {
      return request<ApiResponse<{ user: User; tokens: { accessToken: string; refreshToken: string; accessTokenExpiresAt: string } }>>(
        'POST', '/auth/login', data,
      )
    },
    forgotPassword(email: string) {
      return request<ApiResponse<Record<string, never>>>('POST', '/auth/forgot-password', { email })
    },
    resetPassword(data: { email: string; code: string; password: string; device: Device }) {
      return request<ApiResponse<{ user: User; tokens: { accessToken: string; refreshToken: string; accessTokenExpiresAt: string } }>>(
        'POST', '/auth/reset-password', data,
      )
    },
    logout(refreshToken: string) {
      return request<ApiResponse<Record<string, never>>>('POST', '/auth/logout', { refreshToken })
    },
    getProfile() {
      return request<ApiResponse<User>>('GET', '/users/me', undefined, true)
    },
    updateProfile(data: Partial<Pick<User, 'displayName' | 'bio' | 'city' | 'occupation' | 'birthDate' | 'interests' | 'relationshipStatus' | 'showDistance'>>) {
      return request<ApiResponse<User>>('PATCH', '/users/me', data, true)
    },
  }
}
