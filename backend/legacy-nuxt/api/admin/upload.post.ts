export default defineEventHandler(async (event) => {
  await requireStaff(event, ['admin', 'manager'])
  const parts = await readMultipartFormData(event)
  const file = parts?.find((p) => p.name === 'file')
  if (!file || !file.data?.length) throw createError({ statusCode: 400, statusMessage: 'File tidak ditemukan.' })
  if ((file.type && !file.type.startsWith('image/')) || !/\.(jpe?g|png|webp|avif|gif)$/i.test(file.filename ?? '')) {
    throw createError({ statusCode: 400, statusMessage: 'Hanya file gambar yang diizinkan.' })
  }
  if (file.data.length > 2 * 1024 * 1024) throw createError({ statusCode: 400, statusMessage: 'Ukuran gambar maksimal 2MB.' })

  const ext = (file.filename ?? 'img.jpg').split('.').pop()?.toLowerCase() ?? 'jpg'
  const path = `products/${crypto.randomUUID()}.${ext}`
  const sb = serviceClient(event)
  const { error } = await sb.storage.from('media').upload(path, file.data, { contentType: file.type ?? 'image/jpeg' })
  if (error) throw createError({ statusCode: 500, statusMessage: 'Gagal mengunggah gambar.' })
  return { url: sb.storage.from('media').getPublicUrl(path).data.publicUrl }
})
