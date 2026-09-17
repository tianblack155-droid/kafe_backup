import { FIELDS, saveProductExtras } from '../../../utils/products'

export default defineEventHandler(async (event) => {
  await requireStaff(event, ['admin', 'manager'])
  const body = await readBody<Record<string, unknown>>(event)
  const values = pickFields(body, FIELDS)

  if (!values.name || typeof values.name !== 'string') throw createError({ statusCode: 400, statusMessage: 'Nama produk wajib diisi.' })
  if (!Number.isInteger(Number(values.price)) || Number(values.price) < 0) throw createError({ statusCode: 400, statusMessage: 'Harga tidak valid.' })
  values.slug = (values.slug as string) || String(values.name).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '') + '-' + Math.random().toString(36).slice(2, 6)
  values.price = Number(values.price)

  const sb = serviceClient(event)
  const { data, error } = await sb.from('products').insert(values).select().single()
  if (error) throw createError({ statusCode: 400, statusMessage: 'Gagal menyimpan produk.' })
  await saveProductExtras(sb, data.id, body as never)
  return data
})
