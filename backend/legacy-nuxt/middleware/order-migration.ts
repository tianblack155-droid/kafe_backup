// Legacy order mutations are disabled after cash-only migration. No dual writers.
export default defineEventHandler((event) => {
  const path = getRequestURL(event).pathname
  if (path === '/api/orders' || path.startsWith('/api/orders/') || path === '/api/admin/orders' || path.startsWith('/api/admin/orders/')) {
    throw createError({ statusCode: 410, statusMessage: 'Gunakan jalur Go cash-only melalui /api/core.' })
  }
})
