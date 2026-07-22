export default defineNuxtRouteMiddleware((to) => {
  if (import.meta.server) return

  const isAuthenticated = !!localStorage.getItem('gonow_access_token')

  if (!isAuthenticated && to.path !== '/login' && to.path !== '/register'
    && to.path !== '/verify-email' && to.path !== '/forgot-password'
    && to.path !== '/reset-password') {
    return navigateTo('/login')
  }

  if (isAuthenticated && (to.path === '/login' || to.path === '/register')) {
    return navigateTo('/map')
  }
})
