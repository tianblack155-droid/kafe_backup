export const CRUD_RESOURCES: Record<string, { fields: string[]; canCreate: boolean }> = {
  categories: { fields: ['name', 'slug', 'sort_order', 'is_active'], canCreate: true },
  addons: { fields: ['name', 'price', 'is_available'], canCreate: true },
  tables: { fields: ['number', 'is_active'], canCreate: true },
  settings: { fields: ['brand_name', 'tagline', 'logo_url', 'tax_pct', 'service_pct', 'require_customer_name'], canCreate: false },
  products: { fields: [], canCreate: false }
}

export function pickFields(body: Record<string, unknown>, fields: string[]) {
  const out: Record<string, unknown> = {}
  for (const f of fields) if (f in body) out[f] = body[f]
  return out
}
