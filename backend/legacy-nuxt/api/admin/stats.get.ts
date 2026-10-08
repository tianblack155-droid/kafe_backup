export default defineEventHandler(async (event) => {
  await requireStaff(event)
  const sb = serviceClient(event)
  const today = new Date(); today.setHours(0, 0, 0, 0)
  const todayIso = today.toISOString()

  const [todayOrders, activeOrders, paidToday, popular] = await Promise.all([
    sb.from('orders').select('status, total, payment_status').gte('created_at', todayIso),
    sb.from('orders').select('id, status').in('status', ['pending', 'preparing', 'ready']),
    sb.from('orders').select('total').gte('created_at', todayIso).eq('payment_status', 'paid'),
    sb.from('order_items').select('product_name, quantity, orders!inner(created_at)').gte('orders.created_at', todayIso)
  ])

  const counts = { pending: 0, preparing: 0, ready: 0, completed: 0, cancelled: 0 } as Record<string, number>
  for (const o of todayOrders.data ?? []) counts[o.status] = (counts[o.status] ?? 0) + 1

  const top = new Map<string, number>()
  for (const it of popular.data ?? []) top.set(it.product_name, (top.get(it.product_name) ?? 0) + it.quantity)

  return {
    today_total: todayOrders.data?.length ?? 0,
    today_revenue: (paidToday.data ?? []).reduce((s, o) => s + o.total, 0),
    active_total: activeOrders.data?.length ?? 0,
    counts,
    popular: [...top.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5).map(([name, qty]) => ({ name, qty }))
  }
})
