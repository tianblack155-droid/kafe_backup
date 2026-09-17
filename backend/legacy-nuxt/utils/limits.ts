import type { H3Event } from 'h3'

// ponytail: in-memory rate limit per process; use Redis/upstash only if multi-instance deploy needs it
const hits = new Map<string, number[]>()

export function rateLimit(event: H3Event, name: string, max: number, windowMs: number) {
  const key = `${name}:${getRequestIP(event, { xForwardedFor: true }) ?? 'unknown'}`
  const now = Date.now()
  const recent = (hits.get(key) ?? []).filter((t) => now - t < windowMs)
  if (recent.length >= max) {
    throw createError({ statusCode: 429, statusMessage: 'Terlalu banyak permintaan. Coba lagi sebentar lagi.' })
  }
  recent.push(now)
  hits.set(key, recent)
}
