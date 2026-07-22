export default defineNuxtConfig({
  compatibilityDate: '2025-07-01',
  modules: ['@nuxt/ui'],

  css: ['~/assets/css/main.css'],

  runtimeConfig: {
    public: {
      apiBase: '/api/v1',
      backendBase: '/api/v1',
    },
  },

  routeRules: {
    '/api/**': { proxy: { to: 'http://127.0.0.1:8080/api/**' } },
    '/health': { proxy: { to: 'http://127.0.0.1:8080/health' } },
  },

  devtools: { enabled: true },

  ssr: false,
})
