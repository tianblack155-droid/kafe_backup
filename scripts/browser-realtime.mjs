// Local E2E: actual Go/Postgres + Nuxt + Caddy WebSocket upgrade; mock Supabase Auth.
// Does not use real credentials or claim live staff authentication coverage.
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright')
import { spawn, execFileSync } from 'node:child_process'
import { createServer } from 'node:http'
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import assert from 'node:assert/strict'
const root = fileURLToPath(new URL('../', import.meta.url))
const database = process.env.BROWSER_TEST_DB || 'teraskayumanis_ws_browser'
if (!/^teraskayumanis_[a-z_]+$/.test(database)) throw new Error('Disposable local DB required')
const sql = query => execFileSync('psql', ['-X', '-At', '-v', 'ON_ERROR_STOP=1', '-d', database, '-c', query], { encoding: 'utf8' }).trim()
const one = query => sql(query).split('\n')[0]
const actor = one("insert into public.profiles(id,role) values(gen_random_uuid(),'cashier') returning id")
const cat = one("insert into public.categories(name,slug) values('WS BROWSER',gen_random_uuid()::text) returning id")
const prod = one(`insert into public.products(category_id,name,slug,price) values('${cat}','Realtime Test Tea',gen_random_uuid()::text,5000) returning id`)
const token = one('insert into public.tables(number) values(99994) returning qr_token')
const access = actor + actor
const jwt = [{ alg: 'HS256', typ: 'JWT' }, { sub: actor, exp: Math.floor(Date.now()/1000)+3600, aud:'authenticated', role:'authenticated' }, 'test-signature'].map((v,i)=>i===2?v:Buffer.from(JSON.stringify(v)).toString('base64url')).join('.')
const auth = createServer((req,res)=>{
  res.setHeader('Content-Type','application/json')
  if (req.headers.authorization !== 'Bearer '+jwt) { res.writeHead(401); res.end('{}'); return }
  res.end(JSON.stringify({id:actor,email:'ws@example.test',aud:'authenticated',role:'authenticated'}))
})
await new Promise(resolve=>auth.listen(5591,'127.0.0.1',resolve))
const temporary = mkdtempSync(join(tmpdir(),'tkm-ws-browser-'))
const config = readFileSync(join(root,'deploy/Caddyfile'),'utf8')
  .replace('teraskayumanis.alrizky.id {','http://127.0.0.1:5594 {')
  .replaceAll('127.0.0.1:8080','127.0.0.1:5592').replaceAll('127.0.0.1:3000','127.0.0.1:5593')
writeFileSync(join(temporary,'Caddyfile'),'{\n admin off\n auto_https off\n}\n'+config)
const children = []
function start(cmd,args,env) {
 const child=spawn(cmd,args,{cwd:root,env:{...process.env,...env},stdio:'ignore'})
 children.push(child)
 return child
}
const goEnv = {DATABASE_URL:`postgres://root@localhost/${database}?host=/var/run/postgresql`,HOST:'127.0.0.1',PORT:'5592',APP_ENV:'test',SUPABASE_URL:'http://127.0.0.1:5591',SUPABASE_ANON_KEY:'test-only',REALTIME_ORIGINS:'http://127.0.0.1:5594'}
let go = start(root+'/backend/bin/server',[],goEnv)
start(process.execPath,['frontend/.output/server/index.mjs'],{HOST:'127.0.0.1',PORT:'5593',NUXT_GO_API_URL:'http://127.0.0.1:5592',NUXT_PUBLIC_SUPABASE_URL:'http://127.0.0.1:5591',NUXT_PUBLIC_SUPABASE_ANON_KEY:'test-only'})
start(process.env.CADDY_BIN || 'caddy',['run','--config',join(temporary,'Caddyfile'),'--adapter','caddyfile'],{})
const base='http://127.0.0.1:5594'
let browser
async function eventually(test, ms=15000) {
 const deadline=Date.now()+ms
 let last
 while(Date.now()<deadline) { try { if(await test())return } catch(e){last=e} await new Promise(r=>setTimeout(r,100)) }
 throw last || new Error('Condition not reached')
}
async function create(suffix) {
 const response=await fetch(base+'/api/core/orders',{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':actor+suffix,'X-Order-Token':access},body:JSON.stringify({customer_name:'WS Browser Test',payment_method:'cash',items:[{product_id:prod,quantity:1,variant_ids:[],addon_ids:[],notes:''}]})})
 assert.equal(response.status,201)
 return response.json()
}
try {
 await eventually(async()=> (await fetch(base+'/cashier')).ok)
 await eventually(async()=> (await fetch('http://127.0.0.1:5592/ready')).ok)
 browser=await chromium.launch({headless:true,args:['--no-sandbox']})
 const page=await browser.newPage(), customer=await browser.newPage(), errors=[], cashierFrames=[], customerFrames=[]
 for (const [p,frames] of [[page,cashierFrames],[customer,customerFrames]]) {
   p.on('pageerror',e=>errors.push(e.message))
   p.on('websocket',ws=>{
     assert.equal(new URL(ws.url()).search,'','No credential query string')
     ws.on('framereceived',frame=>{try{frames.push(JSON.parse(String(frame.payload)))}catch{}})
   })
 }
 await page.route('**/auth/v1/token**',route=>route.fulfill({json:{access_token:jwt,token_type:'bearer',expires_in:3600,expires_at:Math.floor(Date.now()/1000)+3600,refresh_token:'test-refresh-only',user:{id:actor,email:'ws@example.test',aud:'authenticated',role:'authenticated'}}}))
 page.on('dialog',d=>d.accept())
 await page.goto(base+'/cashier')
 await page.getByLabel('Email',{exact:true}).fill('ws@example.test')
 await page.getByLabel('Password',{exact:true}).fill('test-only-password')
 await page.getByRole('button',{name:'Login kasir',exact:true}).click()
 await page.getByText('Realtime tersambung',{exact:true}).waitFor({timeout:12000})
 assert.ok(cashierFrames.some(f=>f.type==='ready'))
 // Prove live delivery, not a successful REST polling check.
 await customer.goto(base+'/menu')
 const menuRow=customer.locator('li').filter({has:customer.getByText('Realtime Test Tea',{exact:true})})
 await menuRow.getByRole('button',{name:'Tambah',exact:true}).click()
 await customer.getByRole('link',{name:'Keranjang',exact:true}).click()
 await customer.waitForURL('**/cart')
 await customer.getByLabel('Nama',{exact:false}).fill('WS Browser Test')
 assert.equal((await customer.context().cookies()).some(c=>c.name==='table_token'),false)
 const submitted=customer.waitForResponse(r=>new URL(r.url()).pathname==='/api/core/orders'&&r.request().method()==='POST')
 const started=Date.now()
 await customer.getByRole('button',{name:'Pesan Sekarang',exact:true}).click()
 const result=await submitted
 assert.equal(result.status(),201)
 assert.equal(Object.hasOwn(result.request().postDataJSON(),'table_token'),false)
 const order=await result.json()
 assert.equal(order.table_id,null);assert.equal(order.tables,null)
 await customer.waitForURL('**/order/'+order.id)
 await eventually(()=>cashierFrames.some(f=>f.type==='order.changed'&&f.order_id===order.id))
 await page.getByText(order.order_number,{exact:false}).waitFor({timeout:6000})
 const orderLatency=Date.now()-started
 await customer.getByText('Realtime tersambung',{exact:true}).waitFor({timeout:10000})
 assert.ok(customerFrames.some(f=>f.type==='ready'))
 const card=page.getByRole('article').filter({hasText:order.order_number+' ·'})
 await card.getByRole('button',{name:'Cek menu / revisi sebelum bayar',exact:true}).click()
 await page.getByRole('button',{name:'Menu tersedia dan pelanggan setuju — Simpan',exact:true}).click()
 await card.getByRole('button',{name:'Konfirmasi tunai lunas',exact:true}).click()
 await customer.getByText('Lunas',{exact:true}).waitFor({timeout:6000})
 assert.ok(customerFrames.some(f=>f.type==='order.changed'&&f.order_id===order.id))
 await card.getByRole('button',{name:'Semua item sudah diantar — Selesai',exact:true}).click()
 await eventually(()=>sql(`select status from public.orders where id='${order.id}'`)==='completed')
 await eventually(()=>customerFrames.some(f=>f.type==='order.changed'&&f.order_id===order.id&&f.event_type?.toUpperCase().includes('COMPLETED')))
 await eventually(async()=> !(await page.getByText(order.order_number,{exact:false}).count()))
 // Go restart closes sockets; new connections must resubscribe and resync.
 const before=cashierFrames.filter(f=>f.type==='ready').length
 go.kill('SIGTERM')
 await new Promise(resolve=>go.once('exit',resolve))
 go=start(root+'/backend/bin/server',[],goEnv)
 await eventually(()=>cashierFrames.filter(f=>f.type==='ready').length>before,20000)
 const after=await create('restart')
 await page.getByText(after.order_number,{exact:false}).waitFor({timeout:6000})
 assert.ok(cashierFrames.some(f=>f.type==='order.changed'&&f.order_id===after.id))
 assert.ok(!customerFrames.some(f=>f.type==='order.changed'&&f.order_id===after.id),'Customer receives no other order')
 await page.getByRole('button',{name:'Keluar',exact:true}).click()
 await page.getByRole('button',{name:'Login kasir',exact:true}).waitFor()
 assert.deepEqual(errors,[])
 console.log(JSON.stringify({result:'PASS',transport:'actual Caddy WebSocket upgrade',auth:'local mock only',orderLatencyMs:orderLatency,checkoutEvent:true,paymentEvent:true,completionEvent:true,restartReconnect:true,customerIsolation:true,logout:true}))
} finally {
 if(browser)await browser.close()
 for(const p of children)if(p.exitCode===null)p.kill('SIGTERM')
 await Promise.all(children.filter(p=>p.exitCode===null).map(p=>new Promise(resolve=>{p.once('exit',resolve);setTimeout(resolve,5000).unref()})))
 auth.close()
 sql(`delete from tkm.checkout_keys where order_id in(select id from public.orders where id in(select order_id from public.order_items where product_id='${prod}'));delete from tkm.outbox_events where order_id in(select id from public.orders where id in(select order_id from public.order_items where product_id='${prod}'));delete from public.payments where order_id in(select id from public.orders where id in(select order_id from public.order_items where product_id='${prod}'));delete from public.orders where id in(select order_id from public.order_items where product_id='${prod}');delete from public.tables where qr_token='${token}';delete from public.products where id='${prod}';delete from public.categories where id='${cat}';delete from public.profiles where id='${actor}';`)
 rmSync(temporary,{recursive:true,force:true})
}
