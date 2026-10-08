export default defineEventHandler(async (event) => {
  await requireStaff(event, ['admin', 'manager'])
  const id = getRouterParam(event, 'id') ?? ''
  const token = Array.from(crypto.getRandomValues(new Uint8Array(18))).map((b) => b.toString(16).padStart(2, '0')).join('')
  const { error } = await serviceClient(event).from('tables').update({ qr_token: token }).eq('id', id)
  if (error) throw createError({ statusCode: 500, statusMessage: 'Gagal membuat ulang token.' })
  return { qr_token: token }
})
