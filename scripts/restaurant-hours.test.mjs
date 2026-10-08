import test from 'node:test'
import assert from 'node:assert/strict'
import { restaurantHours, restaurantStatus } from '../frontend/shared/restaurant-hours.ts'

test('open status uses Bandung time even when the device is in another timezone', () => {
  assert.equal(restaurantStatus(new Date('2026-10-05T03:00:00Z')).isOpen, true)
  assert.equal(restaurantStatus(new Date('2026-10-05T02:59:59Z')).isOpen, false)
  assert.equal(restaurantStatus(new Date('2026-10-05T14:59:59Z')).isOpen, true)
  assert.equal(restaurantStatus(new Date('2026-10-05T15:00:00Z')).isOpen, false)
})

test('closed status distinguishes opening today and tomorrow; local midnight selects the right day', () => {
  assert.equal(restaurantStatus(new Date('2026-10-05T02:00:00Z')).detail, 'Buka pukul 10:00')
  assert.equal(restaurantStatus(new Date('2026-10-05T15:00:00Z')).detail, 'Buka besok pukul 10:00')
  assert.equal(restaurantStatus(new Date('2026-10-04T17:00:00Z')).dayIndex, 0)
  assert.equal(restaurantStatus(new Date('2026-10-04T16:59:59Z')).dayIndex, 6)
  assert.equal(restaurantHours.length, 7)
})
