import type { Order } from '#shared/types'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

// ponytail: order uuid acts as the access capability; upgrade to signed access tokens if orders ever carry sensitive data
export default defineEventHandler(async (event): Promise<Order> => {
  const uuid = getRouterParam(event, 'uuid') ?? ''
  if (!UUID.test(uuid)) throw createError({ statusCode: 404, statusMessage: 'Pesanan tidak ditemukan.' })

  const { data, error } = await serviceClient(event)
    .from('orders')
    .select('*, tables(number), order_items(*, order_item_addons(addon_name, price))')
    .eq('id', uuid).single()
  if (error || !data) throw createError({ statusCode: 404, statusMessage: 'Pesanan tidak ditemukan.' })
  return data as unknown as Order
})
