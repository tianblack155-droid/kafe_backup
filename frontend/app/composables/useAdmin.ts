import type { StaffRole } from '#shared/types'

interface AdminMe {
  email: string
  profile: { id: string; full_name: string | null; role: StaffRole }
}

export function useAdmin() {
  const me = useState<AdminMe | null>('admin-me', () => null)

  async function load() {
    if (!me.value) me.value = await $fetch<AdminMe>('/api/admin/me')
    return me.value
  }

  async function logout() {
    await useSupabase().auth.signOut()
    me.value = null
    await navigateTo('/admin/login')
  }

  const can = (roles: StaffRole[]) => !me.value || roles.includes(me.value.profile.role)

  return { me, load, logout, can }
}
