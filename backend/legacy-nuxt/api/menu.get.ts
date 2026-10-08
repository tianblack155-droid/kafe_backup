import type { MenuResponse } from '#shared/types'

export default defineEventHandler(async (event): Promise<MenuResponse> => {
  const sb = serviceClient(event)
  const [cats, prods, variants, links, addons, settings] = await Promise.all([
    sb.from('categories').select('*').eq('is_active', true).order('sort_order'),
    sb.from('products').select('*').order('created_at'),
    sb.from('product_variants').select('*').order('sort_order'),
    sb.from('product_addons').select('product_id, addon_id'),
    sb.from('addons').select('*'),
    sb.from('settings').select('*').eq('id', 1).single()
  ])
  if (cats.error || prods.error || variants.error || links.error || addons.error || settings.error) {
    throw createError({ statusCode: 500, statusMessage: 'Gagal memuat menu. Coba lagi.' })
  }
  const addonList = addons.data ?? []
  const activeCatIds = new Set((cats.data ?? []).map((c) => c.id))
  return {
    settings: settings.data,
    categories: cats.data ?? [],
    products: (prods.data ?? [])
      .filter((p) => activeCatIds.has(p.category_id))
      .map((p) => ({
        ...p,
        variants: (variants.data ?? []).filter((v) => v.product_id === p.id),
        addons: addonList.filter((a) => (links.data ?? []).some((l) => l.product_id === p.id && l.addon_id === a.id))
      }))
  }
})
