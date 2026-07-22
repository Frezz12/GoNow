import type { User } from '~/utils/types'
import { getStoredUser, saveUser, saveTokens, clearSession, getStoredTokens } from '~/utils/auth-storage'
import { authApi } from './use-api'
import { getDevice } from '~/utils/device'

export function useAuth() {
  const user = useState<User | null>('auth-user', () => null)
  const isAuthenticated = computed(() => !!getStoredTokens().accessToken)

  function afterLogin(u: User, tokens: { accessToken: string; refreshToken: string; accessTokenExpiresAt: string }) {
    user.value = u
    saveUser(u)
    saveTokens(tokens.accessToken, tokens.refreshToken, tokens.accessTokenExpiresAt)
  }

  function init() {
    user.value = getStoredUser()
  }

  async function register(email: string, password: string, displayName: string, username: string) {
    const res = await authApi().register({ email, password, displayName, username, device: getDevice() })
    return res.data
  }

  async function verifyEmail(email: string, code: string) {
    const res = await authApi().verifyEmail({ email, code, device: getDevice() })
    afterLogin(res.data.user, res.data.tokens)
  }

  async function login(email: string, password: string) {
    const res = await authApi().login({ email, password, device: getDevice() })
    afterLogin(res.data.user, res.data.tokens)
  }

  async function forgotPassword(email: string) {
    await authApi().forgotPassword(email)
  }

  async function resetPassword(email: string, code: string, password: string) {
    const res = await authApi().resetPassword({ email, code, password, device: getDevice() })
    afterLogin(res.data.user, res.data.tokens)
  }

  async function logout() {
    const { refreshToken } = getStoredTokens()
    try {
      if (refreshToken) await authApi().logout(refreshToken)
    } catch { /* ignore */ }
    user.value = null
    clearSession()
    navigateTo('/login')
  }

  async function refreshUser() {
    if (!isAuthenticated.value) return
    try {
      const res = await authApi().getProfile()
      user.value = res.data
      saveUser(res.data)
    } catch { /* ignore */ }
  }

  return {
    user,
    isAuthenticated,
    init,
    register,
    verifyEmail,
    login,
    forgotPassword,
    resetPassword,
    logout,
    refreshUser,
  }
}
