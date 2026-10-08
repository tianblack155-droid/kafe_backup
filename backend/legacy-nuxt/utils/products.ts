import type { Variant } from '#shared/types'

const FIELDS = ['category_id', 'name', 'slug', 'description', 'price', 'image_url', 'is_available', 'is_featured', 'is_best_seller', 'is_new']

export async function saveProductExtras(sb: ReturnType<typeof serviceClient>, productId: string, body: { variants?: Variant[]; addon_ids?: string[] }) {
  // ponytail: no transaction across product+variants+addons; RPC wrap if partial writes ever bite
  if (Array.isArray(body.variants)) {
    const keep = body.variants.filter((v) => v.id).map((v) => v.id)
    if (keep.length) await sb.from('product_variants').delete().eq('product_id', productId).not('id', 'in', `(${keep.join(',')})`)
    else await sb.from('product_variants').delete().eq('product_id', productId)
    for (const v of body.variants) {
      const values = {
        product_id: productId,
        group_name: v.group_name || 'Pilihan',
        name: v.name,
        price_modifier: Number(v.price_modifier) || 0,
        is_default: !!v.is_default,
        is_available: v.is_available !== false,
        sort_order: Number(v.sort_order) || 0
      }
      if (!values.name) continue
      if (v.id) await sb.from('product_variants').update(values).eq('id', v.id).eq('product_id', productId)
      else await sb.from('product_variants').insert(values)
    }
  }
  if (Array.isArray(body.addon_ids)) {
    await sb.from('product_addons').delete().eq('product_id', productId)
    if (body.addon_ids.length) {
      await sb.from('product_addons').insert(body.addon_ids.map((addonId) => ({ product_id: productId, addon_id: addonId })))
    }
  }
}

export { FIELDS }
