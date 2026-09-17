export default defineEventHandler(async (event) => {
  const me = await requireStaff(event)
  return { email: me.email, profile: { id: me.id, full_name: me.full_name, role: me.role } }
})
