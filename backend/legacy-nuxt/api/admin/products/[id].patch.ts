import { FIELDS, saveProductExtras } from '../../../utils/products'

export default defineEventHandler(async (event) => {
  await requireStaff(event, ['admin', 'manager'])
  const id = getRouterParam(event, 'id') ?? ''
  const body = await readBody<Record<string, unknown>>(event)
  const values = pickFields(body, FIELDS)
  if (values.price !== undefined) {
    if (!Number.isInteger(Number(values.price)) || Number(values.price) < 0) throw createError({ statusCode: 400, statusMessage: 'Harga tidak valid.' })
    values.price = Number(values.price)
  }
  if (values.slug) delete values.slug

  const sb = serviceClient(event)
  if (Object.keys(values).length) {
    const { error } = await sb.from('products').update(values).eq('id', id)
    if (error) throw createError({ statusCode: 400, statusMessage: 'Gagal memperbarui produk.' })
  }
  await saveProductExtras(sb, id, body as never)
  return { ok: true }
})
