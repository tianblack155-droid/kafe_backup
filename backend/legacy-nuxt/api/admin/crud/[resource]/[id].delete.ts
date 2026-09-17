export default defineEventHandler(async (event) => {
  await requireStaff(event, ['admin', 'manager'])
  const resource = getRouterParam(event, 'resource') ?? ''
  const id = getRouterParam(event, 'id') ?? ''
  if (!CRUD_RESOURCES[resource] || resource === 'settings') {
    throw createError({ statusCode: 404, statusMessage: 'Tidak dapat menghapus data ini.' })
  }
  const { error } = await serviceClient(event).from(resource).delete().eq('id', id)
  if (error) throw createError({ statusCode: 400, statusMessage: 'Gagal menghapus. Data mungkin masih dipakai.' })
  return { ok: true }
})
