import type { OrderStatus, PaymentStatus } from '#shared/types'

const STATUS_FLOW: Record<OrderStatus, OrderStatus[]> = {
  pending: ['preparing', 'cancelled'],
  confirmed: [],
  expired: [],
  preparing: ['ready', 'cancelled'],
  ready: ['completed', 'cancelled'],
  completed: [],
  cancelled: []
}
const PAYMENT_FLOW: Record<PaymentStatus, PaymentStatus[]> = {
  unpaid: ['pending', 'paid'],
  pending: ['paid', 'failed'],
  paid: ['refunded'],
  failed: ['unpaid'],
  refunded: []
}

export default defineEventHandler(async (event) => {
  const staff = await requireStaff(event)
  const id = getRouterParam(event, 'id') ?? ''
  const body = await readBody<{ status?: OrderStatus; payment_status?: PaymentStatus }>(event)

  if (body.payment_status) {
    await requireStaff(event, ['admin', 'manager', 'cashier'])
  }

  const sb = serviceClient(event)
  const { data: order } = await sb.from('orders').select('id, status, payment_status').eq('id', id).single()
  if (!order) throw createError({ statusCode: 404, statusMessage: 'Pesanan tidak ditemukan.' })

  const patch: Record<string, string> = {}
  if (body.status && body.status !== order.status) {
    if (!(STATUS_FLOW[order.status as OrderStatus] ?? []).includes(body.status)) {
      throw createError({ statusCode: 400, statusMessage: `Perubahan status ${order.status} → ${body.status} tidak diizinkan.` })
    }
    patch.status = body.status
  }
  if (body.payment_status && body.payment_status !== order.payment_status) {
    if (!(PAYMENT_FLOW[order.payment_status as PaymentStatus] ?? []).includes(body.payment_status)) {
      throw createError({ statusCode: 400, statusMessage: 'Perubahan status pembayaran tidak diizinkan.' })
    }
    patch.payment_status = body.payment_status
  }
  if (Object.keys(patch).length === 0) return { ok: true }

  const { error } = await sb.from('orders').update(patch).eq('id', id)
  if (error) throw createError({ statusCode: 500, statusMessage: 'Gagal memperbarui pesanan.' })

  if (patch.status) {
    await sb.from('order_status_history').insert({
      order_id: id,
      old_status: order.status,
      new_status: patch.status,
      changed_by: staff.id
    })
  }
  return { ok: true }
})
