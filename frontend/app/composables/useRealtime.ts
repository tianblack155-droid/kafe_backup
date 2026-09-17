import { createRealtimeController, realtimeURL } from '#shared/realtime'
import type { RealtimeOptions } from '#shared/realtime'

// Created by the page on mount; dispose on unmount. No credentials in URLs,
// persistent stores, or event payloads. Supabase session lookup belongs to subscribe.
export function useRealtime<T>(options: Omit<RealtimeOptions<T>, 'url'>) {
  const controller = createRealtimeController<T>({
    ...options,
    url: realtimeURL(window.location.href),
    createSocket: url => new WebSocket(url),
    setTimeout: (fn, ms) => setTimeout(fn, ms),
    clearTimeout: id => clearTimeout(id)
  })
  const focus = () => controller.refresh()
  const online = () => controller.refresh()
  const visible = () => { if (document.visibilityState === 'visible') controller.refresh() }
  window.addEventListener('focus', focus)
  window.addEventListener('online', online)
  document.addEventListener('visibilitychange', visible)
  return {
    ...controller,
    dispose() {
      controller.stop()
      window.removeEventListener('focus', focus)
      window.removeEventListener('online', online)
      document.removeEventListener('visibilitychange', visible)
    }
  }
}
