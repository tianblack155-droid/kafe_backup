export default defineEventHandler(async (event) => {
  await requireStaff(event, ['admin', 'manager'])
  const resource = getRouterParam(event, 'resource') ?? ''
  const def = CRUD_RESOURCES[resource]
  if (!def || !def.canCreate) throw createError({ statusCode: 404, statusMessage: 'Tidak dapat membuat data ini.' })

  const body = await readBody<Record<string, unknown>>(event)
  const values = pickFields(body, def.fields)
  if (Object.keys(values).length === 0) throw createError({ statusCode: 400, statusMessage: 'Data tidak valid.' })

  const { data, error } = await serviceClient(event).from(resource).insert(values).select().single()
  if (error) throw createError({ statusCode: 400, statusMessage: 'Gagal menyimpan. Periksa kembali data Anda.' })
  return data
})
