import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'
const root=resolve(import.meta.dirname,'..')
test('active checkout is cash only and uses the Go proxy',()=>{
 const s=readFileSync(resolve(root,'frontend/app/pages/cart.vue'),'utf8')
 assert.ok(!s.includes("id: 'qris'"))
 assert.ok(s.includes("'/api/core/orders'"))
 assert.ok(s.includes('Idempotency-Key'))
 assert.ok(s.includes('X-Order-Token'))
})
test('cashier confirms paid separately from all delivered',()=>{
 const s=readFileSync(resolve(root,'frontend/app/pages/cashier.vue'),'utf8')
 assert.ok(s.includes('confirm-cash'))
 assert.ok(s.includes('/complete'))
 assert.ok(s.includes('Semua item sudah diantar'))
})
