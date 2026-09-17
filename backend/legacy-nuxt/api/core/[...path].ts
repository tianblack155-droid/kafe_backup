// Same-origin BFF: no business logic, credential injection, or arbitrary proxy URL.
export default defineEventHandler(async (event) => {
  const base = useRuntimeConfig(event).goApiUrl as string
  if (!base) throw createError({ statusCode: 503, statusMessage: 'Backend Go belum dikonfigurasi.' })
  const path = getRouterParam(event, 'path') ?? ''
  if (!/^(menu|table|orders|admin\/orders)(\/[a-zA-Z0-9-]+)*$/.test(path)) {
    throw createError({ statusCode: 404 })
  }
  const query = getRequestURL(event).search
  return proxyRequest(event, `${base.replace(/\/$/, '')}/api/v1/${path}${query}`, {
    fetchOptions: { redirect: 'error', signal: AbortSignal.timeout(15000) },
    headers: {
      authorization: getHeader(event, 'authorization') ?? '',
      'x-order-token': getHeader(event, 'x-order-token') ?? '',
      'idempotency-key': getHeader(event, 'idempotency-key') ?? '',
      cookie: '',
    },
  })
})
