import type { CartLine, CreateOrderPayload, Product } from './types.ts'

// Only this checkout-specific server code proves the attempt did not commit.
// Generic conflicts, identity mismatches and transport errors remain unresolved.
export function isCheckoutRejected(error: unknown) {
  const e = error as { status?: number; statusCode?: number; data?: { code?: string } } | null
  return (e?.status ?? e?.statusCode) === 409 && e?.data?.code === 'checkout_rejected'
}

export function remainingSeconds(expiresAt: string, now: number) {
  return Math.max(0, Math.ceil((Date.parse(expiresAt) - now) / 1000))
}
export function canAcceptCash(order: {status: string; payment_status: string; version: number; reviewed_version: number | null; expires_at: string}, now: number) {
  return order.status === 'pending' && order.payment_status === 'unpaid' && order.reviewed_version === order.version && remainingSeconds(order.expires_at, now) > 0
}
export function prepareReorder(payload: CreateOrderPayload, products: Product[]) {
  const lines: CartLine[] = [], errors: string[] = []
  let subtotal = 0
  for (const [index, item] of payload.items.entries()) {
    const p = products.find(p => p.id === item.product_id)
    const variants = p?.variants.filter(v => item.variant_ids.includes(v.id)) ?? []
    const addons = p?.addons.filter(a => item.addon_ids.includes(a.id)) ?? []
    const requiredGroups = new Set(p?.variants.filter(v => v.is_available).map(v => v.group_name))
    const selectedGroups = new Set(variants.map(v => v.group_name))
    if (!p?.is_available || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 50 ||
      variants.length !== item.variant_ids.length || addons.length !== item.addon_ids.length ||
      variants.some(v => !v.is_available) || addons.some(a => !a.is_available) ||
      selectedGroups.size !== variants.length || [...requiredGroups].some(g => !selectedGroups.has(g))) {
      errors.push(`${p?.name ?? 'Menu lama'}: tidak tersedia atau pilihannya berubah. Pilih ulang menu tersebut.`)
    }
    lines.push({ key: `reorder-${index}`, productId: item.product_id, variantIds: [...item.variant_ids], addonIds: [...item.addon_ids], qty: item.quantity, notes: item.notes ?? '' })
    subtotal += ((p?.price ?? 0) + variants.reduce((s,v) => s+v.price_modifier,0) + addons.reduce((s,a) => s+a.price,0)) * item.quantity
  }
  return { lines, errors, subtotal }
}
