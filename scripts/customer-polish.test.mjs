import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8')
test('landing preserves real contacts and separates tutorial and dine entry from details',()=>{
 const s=read('frontend/app/pages/index.vue')
 assert.ok(s.indexOf('customer-entry-actions')>s.indexOf('</section>'))
 for(const value of ['customer-tutorial-entry','customer-dine-entry','https://maps.app.goo.gl/64bfw1KhogyUspXN6','https://wa.me/6282246851927','https://www.instagram.com/teraskayumanis.id/','allevi-dev.webp']) assert.ok(s.includes(value))
 assert.doesNotMatch(s,/7 Km|Tutup 21:30|Bakmi GM/)
})
test('product recommendations precede options without changing selection limits',()=>{
 const s=read('frontend/app/pages/menu/[id].vue')
 assert.ok(s.indexOf('class="customer-recommendations"')<s.indexOf('<form id="product-selection"'))
 assert.match(s,/maxlength="200"/)
 assert.match(s,/selection.qty >= 50/)
})
