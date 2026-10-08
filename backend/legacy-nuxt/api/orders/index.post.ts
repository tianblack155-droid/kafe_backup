import type { CreateOrderPayload } from '#shared/types'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export default defineEventHandler(async (event) => {
  rateLimit(event, 'create-order', 10, 60_000)
  const body = await readBody<CreateOrderPayload>(event)

  if (!body?.table_token || typeof body.table_token !== 'string') {
    throw createError({ statusCode: 400, statusMessage: 'Meja tidak dikenali. Silakan scan ulang QR.' })
  }
  if (!Array.isArray(body.items) || body.items.length === 0 || body.items.length > 50) {
    throw createError({ statusCode: 400, statusMessage: 'Keranjang tidak valid.' })
  }
  const variantIds = new Set<string>()
  for (const item of body.items) {
    if (!UUID.test(item?.product_id ?? '')) {
      throw createError({ statusCode: 400, statusMessage: 'Pesanan tidak valid.' })
    }
    for (const id of item?.variant_ids ?? []) {
      if (!UUID.test(id)) throw createError({ statusCode: 400, statusMessage: 'Pesanan tidak valid.' })
      variantIds.add(id)
    }
    if (!Array.isArray(item.addon_ids) || item.addon_ids.some((id: string) => !UUID.test(id))) {
      throw createError({ statusCode: 400, statusMessage: 'Pesanan tidak valid.' })
    }
    if (!Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 50) {
      throw createError({ statusCode: 400, statusMessage: 'Jumlah pesanan tidak valid.' })
    }
  }

  const { data, error } = await serviceClient(event).rpc('create_order', {
    payload: {
      table_token: body.table_token,
      customer_name: typeof body.customer_name === 'string' ? body.customer_name : '',
      payment_method: body.payment_method === 'qris' ? 'qris' : 'cash',
      items: body.items.map((i) => ({
        product_id: i.product_id,
        variant_ids: i.variant_ids ?? [],
        addon_ids: i.addon_ids,
        quantity: i.quantity,
        notes: typeof i.notes === 'string' ? i.notes : ''
      }))
    }
  })
  if (error) throw createError({ statusCode: 400, statusMessage: error.message })
  return data
})
