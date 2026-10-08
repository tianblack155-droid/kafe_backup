import type { Order, OrderStatus } from '#shared/types'

export default defineEventHandler(async (event): Promise<Order[]> => {
  await requireStaff(event)
  const q = getQuery(event)
  let query = serviceClient(event)
    .from('orders')
    .select('*, tables(number), order_items(*, order_item_addons(addon_name, price))')
    .order('created_at', { ascending: false })
    .limit(100)
  if (q.status) query = query.in('status', String(q.status).split(','))
  if (q.table_id) query = query.eq('table_id', String(q.table_id))
  const { data, error } = await query
  if (error) throw createError({ statusCode: 500, statusMessage: 'Gagal memuat pesanan.' })
  return (data as unknown as Order[])
})
