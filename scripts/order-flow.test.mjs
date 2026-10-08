import test from 'node:test'
import assert from 'node:assert/strict'
import { prepareReorder, canAcceptCash, remainingSeconds } from '../frontend/shared/order-flow.ts'
const product={id:'p',name:'Kopi',price:24000,is_available:true,variants:[],addons:[]}
const payload={table_token:'table',customer_name:'A',payment_method:'cash',items:[{product_id:'p',quantity:2,variant_ids:[],addon_ids:[],notes:''}]}
test('reorder builds cart at current prices, without mutating old payload',()=>{
 const result=prepareReorder(payload,[product]);assert.equal(result.subtotal,48000);assert.equal(result.lines[0].qty,2);assert.deepEqual(result.errors,[]);assert.equal(payload.items[0].product_id,'p')
})
test('unavailable or removed choices cannot silently become a different order',()=>{
 assert.equal(prepareReorder(payload,[{...product,is_available:false}]).errors.length,1)
 assert.equal(prepareReorder({...payload,items:[{...payload.items[0],variant_ids:['gone']}]},[product]).errors.length,1)
})
test('payment requires reviewed current version, pending, unpaid and unexpired',()=>{
 const o={status:'pending',payment_status:'unpaid',version:2,reviewed_version:2,expires_at:'2026-09-16T01:15:00Z'}
 assert.equal(canAcceptCash(o,Date.parse('2026-09-16T01:14:59Z')),true)
 assert.equal(canAcceptCash(o,Date.parse(o.expires_at)),false)
 assert.equal(canAcceptCash({...o,version:3},Date.parse('2026-09-16T01:14:59Z')),false)
 assert.equal(canAcceptCash({...o,status:'expired'},0),false)
 assert.equal(remainingSeconds(o.expires_at,Date.parse('2026-09-16T01:14:59Z')),1)
})
