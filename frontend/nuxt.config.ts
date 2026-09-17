import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  // Transitional Nitro API: source is separated; runtime remains Nuxt until
  // each business endpoint has been migrated and verified in Go.
  serverDir: '../backend/legacy-nuxt',
  css: ['~/assets/css/main.css'],
  vite: { plugins: [tailwindcss()] },
  runtimeConfig: {
    goApiUrl: '',
    supabaseUrl: '',
    supabaseServiceKey: '',
    supabaseAnonKey: '',
    public: {
      supabaseUrl: '',
      supabaseAnonKey: ''
    }
  },
  routeRules: {
    '/admin/**': { ssr: false },
    '/cashier': { ssr: false }
  },
  app: {
    head: {
      title: 'TerasKayuManis',
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        {
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,400..700&family=Inter:wght@400..700&display=swap'
        }
      ]
    }
  }
})
