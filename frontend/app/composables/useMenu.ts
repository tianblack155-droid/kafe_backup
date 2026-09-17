import type { MenuResponse } from '#shared/types'

export function useMenu() {
  const menu = useState<MenuResponse | null>('menu', () => null)
  const loading = useState('menu-loading', () => false)

  async function load(force = false) {
    if (menu.value && !force) return
    loading.value = true
    try {
      menu.value = await $fetch<MenuResponse>('/api/core/menu')
    } finally {
      loading.value = false
    }
  }

  return { menu, loading, load }
}
