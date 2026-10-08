import type { Category, Product } from './types'

export interface ProductSelection {
  variantIds: string[]
  addonIds: string[]
  qty: number
  notes: string
}

export function variantGroups(product: Product) {
  const groups = new Map<string, Product['variants']>()
  for (const variant of product.variants) {
    groups.set(variant.group_name, [...(groups.get(variant.group_name) ?? []), variant])
  }
  return [...groups.entries()]
}

export function defaultSelection(product: Product): ProductSelection {
  return {
    variantIds: variantGroups(product).flatMap(([, variants]) => {
      const choice = variants.find(v => v.is_available && v.is_default) ?? variants.find(v => v.is_available)
      return choice ? [choice.id] : []
    }),
    addonIds: [], qty: 1, notes: ''
  }
}

// Client feedback only. Checkout/server remain authoritative for stale availability/prices.
export function validateSelection(product: Product, selection: ProductSelection): string[] {
  const errors: string[] = []
  if (!product.is_available) errors.push('Menu ini sedang tidak tersedia.')
  if (!Number.isInteger(selection.qty) || selection.qty < 1 || selection.qty > 50) errors.push('Jumlah harus 1–50.')
  if (selection.notes.length > 200) errors.push('Catatan maksimal 200 karakter.')
  if (new Set(selection.variantIds).size !== selection.variantIds.length || selection.variantIds.some(id => !product.variants.some(v => v.id === id && v.is_available))) errors.push('Pilihan varian tidak tersedia. Pilih ulang.')
  for (const [name, variants] of variantGroups(product)) {
    const available = variants.filter(v => v.is_available)
    if (available.length && available.filter(v => selection.variantIds.includes(v.id)).length !== 1) errors.push(`Pilih satu varian ${name} yang tersedia.`)
  }
  if (new Set(selection.addonIds).size !== selection.addonIds.length || selection.addonIds.some(id => !product.addons.some(a => a.id === id && a.is_available))) errors.push('Tambahan tidak tersedia. Pilih ulang.')
  return errors
}

export function selectionPrice(product: Product, selection: ProductSelection): number {
  return product.price + product.variants.filter(v => selection.variantIds.includes(v.id)).reduce((sum, v) => sum + v.price_modifier, 0)
    + product.addons.filter(a => selection.addonIds.includes(a.id)).reduce((sum, a) => sum + a.price, 0)
}

export function recommendations(products: Product[], currentId: string) {
  return products.filter(p => p.id !== currentId && p.is_available).slice(0, 6)
}

export function groupProducts(categories: Category[], products: Product[], query: string) {
  const q = query.trim().toLocaleLowerCase('id')
  return categories.filter(c => c.is_active).map(category => ({ category,
    products: products.filter(p => p.category_id === category.id && (!q || `${p.name} ${p.description ?? ''}`.toLocaleLowerCase('id').includes(q)))
  })).filter(group => group.products.length)
}
