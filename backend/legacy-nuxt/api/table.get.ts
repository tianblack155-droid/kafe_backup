export default defineEventHandler(async (event) => {
  const token = getQuery(event).t as string | undefined
  if (!token || !/^[a-f0-9]{16,64}$/i.test(token)) {
    throw createError({ statusCode: 404, statusMessage: 'QR tidak valid. Silakan scan ulang.' })
  }
  const { data, error } = await serviceClient(event)
    .from('tables').select('number').eq('qr_token', token).eq('is_active', true).single()
  if (error || !data) {
    throw createError({ statusCode: 404, statusMessage: 'QR tidak valid atau meja tidak aktif.' })
  }
  return { number: data.number }
})
