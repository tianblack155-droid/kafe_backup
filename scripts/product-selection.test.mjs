import test from 'node:test'
import assert from 'node:assert/strict'
import { defaultSelection, validateSelection, selectionPrice, recommendations, groupProducts } from '../frontend/shared/product-selection.ts'
const p = { id:'p', category_id:'c', name:'Kopi', description:null, price:20000, is_available:true, variants:[{id:'v',group_name:'Ukuran',is_default:true,is_available:true,price_modifier:3000},{id:'off',group_name:'Ukuran',is_default:true,is_available:false,price_modifier:0}], addons:[{id:'a',is_available:true,price:2000},{id:'gone',is_available:false,price:1000}] }
test('defaults choose only available variants and fresh state',()=>{const s=defaultSelection(p);assert.deepEqual(s,{variantIds:['v'],addonIds:[],qty:1,notes:''});s.addonIds.push('a');assert.deepEqual(defaultSelection(p).addonIds,[])})
test('valid selection prices current options without mutating input',()=>{const s={...defaultSelection(p),addonIds:['a'],qty:2};assert.deepEqual(validateSelection(p,s),[]);assert.equal(selectionPrice(p,s),25000);assert.equal(s.qty,2)})
test('quantity must be an integer from 1 through 50 and notes at most 200',()=>{for(const qty of [0,51,1.5,NaN,Infinity])assert.ok(validateSelection(p,{...defaultSelection(p),qty}).length);for(const qty of [1,50])assert.deepEqual(validateSelection(p,{...defaultSelection(p),qty,notes:'x'.repeat(200)}),[]);assert.ok(validateSelection(p,{...defaultSelection(p),notes:'x'.repeat(201)}).length)})
test('reject unavailable product, stale options, duplicate and missing group choices',()=>{const s=defaultSelection(p);assert.ok(validateSelection({...p,is_available:false},s).length);for(const variantIds of [[],['off'],['missing'],['v','v'],['v','off']])assert.ok(validateSelection(p,{...s,variantIds}).length);for(const addonIds of [['gone'],['missing'],['a','a']])assert.ok(validateSelection(p,{...s,addonIds}).length);assert.ok(validateSelection({...p,variants:p.variants.map(v=>({...v,is_available:false}))},s).length)})
test('recommendations only contain actual available other products',()=>{const other={...p,id:'other'};assert.deepEqual(recommendations([p,other,{...p,id:'out',is_available:false}],'p'),[other])})
test('all-unavailable groups are optional, but selected unavailable options remain invalid', () => {
  const unavailable = {...p, variants: p.variants.map(v => ({...v, is_available:false}))}
  assert.deepEqual(validateSelection(unavailable, defaultSelection(unavailable)), [])
  assert.ok(validateSelection(unavailable, {...defaultSelection(unavailable), variantIds:['off']}).length)
  const mixed = {...p, variants:[...p.variants, {id:'sold-out',group_name:'Suhu',is_available:false}]}
  assert.deepEqual(validateSelection(mixed, defaultSelection(mixed)), [])
  assert.ok(validateSelection(mixed, {...defaultSelection(mixed), variantIds:[]}).length)
  assert.ok(validateSelection(mixed, {...defaultSelection(mixed), variantIds:['v','sold-out']}).length)
  const multiple = {...mixed, variants:[...mixed.variants, {id:'hot',group_name:'Suhu',is_available:true}]}
  assert.deepEqual(validateSelection(multiple, defaultSelection(multiple)), [])
  assert.ok(validateSelection(multiple, {...defaultSelection(multiple), variantIds:['v']}).length)
})
test('search matches names/descriptions, excludes inactive and empty categories',()=>{const categories=[{id:'c',is_active:true},{id:'off',is_active:false}];assert.equal(groupProducts(categories,[p],' KOPI ').length,1);assert.equal(groupProducts(categories,[{...p,description:'Segar'}],'segar').length,1);assert.deepEqual(groupProducts(categories,[p],'tea'),[]);assert.deepEqual(groupProducts(categories,[{...p,category_id:'off'}],''),[])})
