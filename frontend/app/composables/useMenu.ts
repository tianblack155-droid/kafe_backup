import type { MenuResponse } from '#shared/types'

export function useMenu() {
  const menu = useState<MenuResponse | null>('menu', () => null)
  const loading = useState('menu-loading', () => false)
  const request = useState('menu-request', () => 0)

  async function load(force = false) {
    if (menu.value && !force) return
    const id = ++request.value
    loading.value = true
    try {
      const result = await $fetch<MenuResponse>('/api/core/menu')
      if (id !== request.value) throw new Error('Catalog request superseded')
      menu.value = result
    } finally {
      if (id === request.value) loading.value = false
    }
  }

  return { menu, loading, load }
}
