import { createClient } from '@supabase/supabase-js'
import { createServerClient } from '@supabase/ssr'
import type { H3Event } from 'h3'
import type { Profile, StaffRole } from '#shared/types'

export function serviceClient(event: H3Event) {
  const config = useRuntimeConfig(event)
  const url = config.supabaseUrl as string
  const key = config.supabaseServiceKey as string
  if (!url || !key) {
    throw createError({ statusCode: 500, statusMessage: 'Server belum dikonfigurasi. Isi env Supabase.' })
  }
  return createClient(url, key, { auth: { persistSession: false } })
}

export async function requireStaff(event: H3Event, roles?: StaffRole[]): Promise<Profile & { email: string }> {
  const config = useRuntimeConfig(event)
  const sb = createServerClient(config.supabaseUrl as string, config.supabaseAnonKey as string, {
    cookies: {
      getAll: () => Object.entries(parseCookies(event)).map(([name, value]) => ({ name, value })),
      setAll: (list: { name: string; value: string }[]) =>
        list.forEach(({ name, value }) => setCookie(event, name, value, { path: '/' }))
    }
  })
  const { data: { user } } = await sb.auth.getUser()
  if (!user) throw createError({ statusCode: 401, statusMessage: 'Silakan login terlebih dahulu.' })

  const { data: profile } = await serviceClient(event)
    .from('profiles').select('*').eq('id', user.id).single()
  if (!profile || (roles && !roles.includes(profile.role))) {
    throw createError({ statusCode: 403, statusMessage: 'Anda tidak memiliki akses.' })
  }
  return { ...profile, email: user.email ?? '' }
}
