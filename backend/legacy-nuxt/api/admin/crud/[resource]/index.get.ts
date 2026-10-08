export default defineEventHandler(async (event) => {
  await requireStaff(event, ['admin', 'manager'])
  const resource = getRouterParam(event, 'resource') ?? ''
  const def = CRUD_RESOURCES[resource]
  if (!def) throw createError({ statusCode: 404, statusMessage: 'Resource tidak ditemukan.' })

  const sb = serviceClient(event)
  if (resource === 'settings') {
    const { data, error } = await sb.from('settings').select('*').eq('id', 1).single()
    if (error) throw createError({ statusCode: 500, statusMessage: 'Gagal memuat pengaturan.' })
    return [data]
  }
  const { data, error } = await sb.from(resource).select('*').order('id')
  if (error) throw createError({ statusCode: 500, statusMessage: 'Gagal memuat data.' })
  return data
})
