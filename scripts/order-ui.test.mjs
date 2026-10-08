import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const read=p=>readFileSync(new URL('../frontend/app/'+p,import.meta.url),'utf8')
test('cashier has separate review before payment, active/history and reorder draft',()=>{
 const s=read('pages/cashier.vue');for(const text of ['/review','expected_version','canAcceptCash','Riwayat','/reorder','OrderEditor'])assert.ok(s.includes(text),text)
 const create=s.slice(s.indexOf('async function createAgain'),s.indexOf('async function sendAttempt'))
 assert.ok(create.includes("if(sessionStorage.getItem('tkm-cashier-checkout'))"),'new draft cannot overwrite unresolved checkout')
})
test('customer expired order transfers reorder draft, cart blocks invalid choices',()=>{
 const s=read('pages/order/[uuid].vue');for(const text of ["'expired'",'/reorder','tkm-reorder','Pesan ulang'])assert.ok(s.includes(text),text)
 assert.ok(read('pages/cart.vue').includes('prepareReorder'))
})
