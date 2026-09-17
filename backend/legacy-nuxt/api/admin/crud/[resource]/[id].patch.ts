export default defineEventHandler(async (event) => {
  await requireStaff(event, ['admin', 'manager'])
  const resource = getRouterParam(event, 'resource') ?? ''
  const id = getRouterParam(event, 'id') ?? ''
  const def = CRUD_RESOURCES[resource]
  if (!def || def.fields.length === 0) throw createError({ statusCode: 404, statusMessage: 'Resource tidak ditemukan.' })

  const body = await readBody<Record<string, unknown>>(event)
  const values = pickFields(body, def.fields)
  if (Object.keys(values).length === 0) throw createError({ statusCode: 400, statusMessage: 'Tidak ada perubahan.' })

  const rowId = resource === 'settings' ? 1 : id
  const { data, error } = await serviceClient(event).from(resource).update(values).eq('id', rowId).select().single()
  if (error || !data) throw createError({ statusCode: 400, statusMessage: 'Gagal memperbarui data.' })
  return data
})
