import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
const file=p=>readFileSync(new URL('../frontend/'+p,import.meta.url),'utf8')
test('active shared QR pages do not read or present table identity',()=>{
 for(const page of ['menu/index.vue','cart.vue','cashier.vue','order/[uuid].vue']){
  const source=file('app/pages/'+page)
  assert.doesNotMatch(source,/useTable\(|route\.query\.t\b|tables\?\.number|Meja belum|Scan QR di meja/i,page)
 }
 assert.doesNotMatch(file('shared/types.ts'),/table_token:\s*string/,'new checkout contract must not require table identity')
})
