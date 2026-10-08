import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { stripTypeScriptTypes } from 'node:module'
import { ref, reactive, computed, watch, effectScope, nextTick } from 'vue'
import * as selections from '../frontend/shared/product-selection.ts'
const root=new URL('../',import.meta.url)
const file=p=>readFileSync(new URL(p,root),'utf8').replace(/\r\n/g,'\n')
const detailSource = () => file('frontend/app/pages/menu/[id].vue')
function detailHarness() {
  const fixture = id => ({id, name:id, price:100, is_available:true, variants:[{id:'default',group_name:'Size',is_available:true,is_default:true,price_modifier:0},{id:'custom',group_name:'Size',is_available:true,price_modifier:10}], addons:[{id:'a',is_available:true,price:10}]})
  const menu = ref({products:[fixture('one'), fixture('two')]})
  const route = reactive({params:{id:'one'}})
  const pending = [], mounted = [], unmounted = []
  const scope = effectScope()
  const bindings = {...selections, ref, computed, watch, useRoute:()=>route,
    useMenu:()=>({menu,loading:ref(false),load:()=>new Promise((resolve,reject)=>pending.push({resolve,reject}))}),
    useCart:()=>({add:()=>{}}), definePageMeta:()=>{}, useHead:()=>{}, navigateTo:async()=>{},
    onMounted:fn=>mounted.push(fn), onUnmounted:fn=>unmounted.push(fn)}
  const script = detailSource().match(/<script setup lang="ts">([\s\S]*?)<\/script>/)[1].replace(/^import .*$/gm,'')
  const run = new Function(...Object.keys(bindings), stripTypeScriptTypes(script)+'; return {ready,selection,error,errors,refresh}')
  const state = scope.run(()=>run(...Object.values(bindings)))
  mounted.forEach(fn=>fn())
  return {state,route,menu,pending,close:()=>{unmounted.forEach(fn=>fn());scope.stop()}}
}
test('cached detail controls are hidden until refresh is ready', () => {
  assert.match(detailSource(), /<template v-if="product && ready">/)
})
test('same-product refresh and object replacements preserve custom choices', async () => {
  const h = detailHarness()
  try {
    assert.equal(h.state.ready.value,false)
    h.pending[0].resolve(); await nextTick()
    Object.assign(h.state.selection.value,{variantIds:['custom'],addonIds:['a'],qty:3,notes:'less sugar'})
    h.menu.value = JSON.parse(JSON.stringify(h.menu.value))
    await nextTick()
    assert.deepEqual({...h.state.selection.value},{variantIds:['custom'],addonIds:['a'],qty:3,notes:'less sugar'})
    const refresh = h.state.refresh()
    assert.equal(h.state.ready.value,false)
    h.menu.value.products[0].variants[1].is_available = false
    h.pending[1].resolve(); await refresh
    assert.equal(h.state.selection.value.notes,'less sugar')
    assert.deepEqual(h.state.selection.value.variantIds,['custom'])
    assert.ok(h.state.errors.value.length, 'preserved stale choices must still fail validation')
    h.route.params.id = 'two'
    assert.equal(h.state.ready.value,false)
    h.pending[2].resolve(); await nextTick()
    assert.deepEqual({...h.state.selection.value},{variantIds:['default'],addonIds:[],qty:1,notes:''})
  } finally {h.close()}
})
test('stale route refresh success or failure cannot expose controls or overwrite current error', async () => {
  for (const rejectOld of [false,true]) {
    const h = detailHarness()
    try {
      h.route.params.id = 'two'; await nextTick()
      if (rejectOld) h.pending[0].reject(new Error('old failure'))
      else h.pending[0].resolve()
      await nextTick()
      assert.equal(h.state.ready.value,false)
      assert.equal(h.state.error.value,'')
      h.pending[1].reject(new Error('current failure')); await nextTick()
      assert.notEqual(h.state.error.value,'')
      assert.equal(h.state.ready.value,false)
      const retry = h.state.refresh()
      h.pending[2].resolve(); await retry
      assert.equal(h.state.ready.value,true)
      assert.equal(h.state.error.value,'')
    } finally {h.close()}
  }
})
test('customer routes use isolated layout; landing does not force redirect',()=>{for(const p of ['index.vue','menu/index.vue','menu/[id].vue','cart.vue','order/[uuid].vue'])assert.match(file('frontend/app/pages/'+p),/layout: 'customer'/);assert.doesNotMatch(file('frontend/app/pages/index.vue'),/redirect:/);assert.match(file('frontend/app/pages/index.vue'),/Makan di Tempat/);assert.match(file('frontend/app/pages/index.vue'),/CustomerModal/)})
test('catalog links to detail, search and category observer reset',()=>{const s=file('frontend/app/pages/menu/index.vue');assert.match(s,/\/menu\//);assert.match(s,/groupProducts/);assert.match(s,/watch\(grouped/);assert.match(s,/observer\?\.disconnect/);assert.match(s,/CustomerModal/);assert.doesNotMatch(s,/<ProductSheet/)})
test('detail validates selection, loads direct links and shows real recommendations',()=>{const s=file('frontend/app/pages/menu/[id].vue');for(const pattern of [/validateSelection/,/load\(/,/route.params.id/,/recommendations/,/maxlength="200"/,/customer-detail-footer/])assert.match(s,pattern)})
test('checkout and tracking scripts remain byte-identical except layout declaration',()=>{for(const p of ['cart.vue','order/[uuid].vue']){const path='frontend/app/pages/'+p;const original=execFileSync('git',['show','HEAD:'+path],{cwd:root,encoding:'utf8'});const script=s=>s.match(/<script setup lang="ts">([\s\S]*?)<\/script>/)[1].replace(/\ndefinePageMeta\(\{ layout: 'customer' \}\)\n/,'');assert.equal(script(file(path)),script(original));assert.equal(file(path).slice(file(path).indexOf('<template>')).replace('customer-legacy ',''),original.slice(original.indexOf('<template>')).replace('customer-legacy ',''))}})
test('customer styles provide mobile sizing, typography and reduced motion',()=>{const css=file('frontend/app/assets/css/customer.css');for(const p of [/Montserrat/,/130px/,/34vw/,/300px/,/120px/,/prefers-reduced-motion/,/44px/])assert.match(css,p);assert.match(file('frontend/app/components/CustomerImage.vue'),/@error/);assert.match(file('frontend/app/components/CustomerModal.vue'),/showModal/);assert.match(file('frontend/app/layouts/customer.vue'),/customer-ui/)})
