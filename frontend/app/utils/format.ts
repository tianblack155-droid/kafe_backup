export function fmtIDR(n: number) {
  return 'Rp' + n.toLocaleString('id-ID')
}

export function timeAgo(iso: string) {
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000)
  if (mins < 1) return 'baru saja'
  if (mins < 60) return `${mins} mnt lalu`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours} jam lalu`
  return `${Math.floor(hours / 24)} hari lalu`
}

export const STATUS_LABEL: Record<string, string> = {
  confirmed: 'Lunas / diproses',
  expired: 'Kedaluwarsa',
  pending: 'Menunggu',
  preparing: 'Disiapkan',
  ready: 'Siap',
  completed: 'Selesai',
  cancelled: 'Batal'
}
