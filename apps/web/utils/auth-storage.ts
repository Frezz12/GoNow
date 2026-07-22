import type { User } from './types'

export const authStorageKeys = {
  accessToken: 'gonow_access_token',
  refreshToken: 'gonow_refresh_token',
  expiresAt: 'gonow_access_expires_at',
  user: 'gonow_user',
} as const

export function getStoredUser(): User | null {
  if (import.meta.server) return null
  const raw = localStorage.getItem(authStorageKeys.user)
  if (!raw) return null
  try {
    return JSON.parse(raw) as User
  } catch {
    return null
  }
}

export function saveUser(user: User) {
  localStorage.setItem(authStorageKeys.user, JSON.stringify(user))
}

export function getStoredTokens() {
  if (import.meta.server) return { accessToken: null, refreshToken: null }
  return {
    accessToken: localStorage.getItem(authStorageKeys.accessToken),
    refreshToken: localStorage.getItem(authStorageKeys.refreshToken),
  }
}

export function saveTokens(access: string, refresh: string, expiresAt: string) {
  localStorage.setItem(authStorageKeys.accessToken, access)
  localStorage.setItem(authStorageKeys.refreshToken, refresh)
  localStorage.setItem(authStorageKeys.expiresAt, expiresAt)
}

export function clearSession() {
  localStorage.removeItem(authStorageKeys.accessToken)
  localStorage.removeItem(authStorageKeys.refreshToken)
  localStorage.removeItem(authStorageKeys.expiresAt)
  localStorage.removeItem(authStorageKeys.user)
}
