// Local restaurant time. Update this schedule when operating hours change.
export const RESTAURANT_TIME_ZONE = 'Asia/Jakarta'
export const restaurantHours = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu']
  .map(day => ({ day, open: '10:00', close: '22:00' }))

const formatter = new Intl.DateTimeFormat('en-US', {
  timeZone: RESTAURANT_TIME_ZONE, weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
})
const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
const minutes = (time: string) => Number(time.slice(0, 2)) * 60 + Number(time.slice(3))

export function restaurantStatus(date: Date) {
  const parts = formatter.formatToParts(date)
  const part = (type: string) => parts.find(item => item.type === type)!.value
  const dayIndex = weekdays.indexOf(part('weekday'))
  const current = Number(part('hour')) * 60 + Number(part('minute'))
  const today = restaurantHours[dayIndex]!
  const isOpen = current >= minutes(today.open) && current < minutes(today.close)
  return {
    dayIndex, isOpen,
    detail: isOpen ? `Tutup pukul ${today.close}` : current < minutes(today.open)
      ? `Buka pukul ${today.open}` : `Buka besok pukul ${restaurantHours[(dayIndex + 1) % 7]!.open}`,
  }
}
