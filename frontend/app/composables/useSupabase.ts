import { createBrowserClient } from '@supabase/ssr'

let client: ReturnType<typeof createBrowserClient> | null = null

export function useSupabase() {
  if (!client) {
    const config = useRuntimeConfig()
    client = createBrowserClient(config.public.supabaseUrl, config.public.supabaseAnonKey)
  }
  return client
}
