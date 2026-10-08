// Local integration only: real Go + PostgreSQL + Nuxt + Chromium, fake Auth service.
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE || 'playwright')
import {spawn,execFileSync} from 'node:child_process'
import {createServer} from 'node:http'
import assert from 'node:assert/strict'
import {fileURLToPath} from 'node:url'
const root=fileURLToPath(new URL('../',import.meta.url))
const database=process.env.BROWSER_TEST_DB || 'teraskayumanis_no_table'
if(!/^teraskayumanis_[a-z_]+$/.test(database))throw new Error('Disposable local DB required')
const sql=s=>execFileSync('psql',['-X','-At','-v','ON_ERROR_STOP=1','-d',database,'-c',s],{encoding:'utf8'}).trim()
const actor=sql("insert into public.profiles(id,role) values(gen_random_uuid(),'cashier') returning id").split('\n')[0]
const cat=sql("insert into public.categories(name,slug) values('BROWSER',gen_random_uuid()::text) returning id").split('\n')[0]
const prod=sql(`insert into public.products(category_id,name,slug,price) values('${cat}','Browser Coffee',gen_random_uuid()::text,12000) returning id`).split('\n')[0]
const table=sql("insert into public.tables(number) values(99995) returning qr_token").split('\n')[0]
const auth=createServer((req,res)=>{res.setHeader('Content-Type','application/json');res.end(JSON.stringify({id:actor,email:'test@example.test',aud:'authenticated',role:'authenticated'}))});await new Promise(r=>auth.listen(4591,'127.0.0.1',r))
const children=[]
function start(cmd,args,env){const p=spawn(cmd,args,{cwd:root,env:{...process.env,...env},stdio:'ignore'});children.push(p);return p}
start(root+'/backend/bin/server',[],{DATABASE_URL:`postgres://root@localhost/${database}?host=/var/run/postgresql`,HOST:'127.0.0.1',PORT:'4592',SUPABASE_URL:'http://127.0.0.1:4591',SUPABASE_ANON_KEY:'test-only'})
start('node',['frontend/.output/server/index.mjs'],{PORT:'4593',HOST:'127.0.0.1',NUXT_GO_API_URL:'http://127.0.0.1:4592',NUXT_PUBLIC_SUPABASE_URL:'http://127.0.0.1:4591',NUXT_PUBLIC_SUPABASE_ANON_KEY:'test-only'})
let browser
async function ready(url){for(let i=0;i<100;i++){try{const r=await fetch(url);if(r.ok)return}catch{}await new Promise(r=>setTimeout(r,100))}throw new Error('not ready '+url)}
try{
 await ready('http://127.0.0.1:4592/health');await ready('http://127.0.0.1:4593/cashier')
 const payload={customer_name:'Browser test',payment_method:'cash',items:[{product_id:prod,quantity:1,variant_ids:[],addon_ids:[],notes:''}]}
 const create=async key=>(await fetch('http://127.0.0.1:4592/api/v1/orders',{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':actor+key,'X-Order-Token':actor+actor},body:JSON.stringify(payload)})).json()
 const order=await create('first');assert.ok(order.id)
 browser=await chromium.launch({headless:true,args:['--no-sandbox']});const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message))
 const jwt=[{alg:'HS256',typ:'JWT'},{sub:actor,exp:Math.floor(Date.now()/1000)+3600,aud:'authenticated',role:'authenticated'},'test-signature'].map((x,i)=>i===2?x:Buffer.from(JSON.stringify(x)).toString('base64url')).join('.')
 await page.route('**/auth/v1/token**',route=>route.fulfill({json:{access_token:jwt,token_type:'bearer',expires_in:3600,expires_at:Math.floor(Date.now()/1000)+3600,refresh_token:'test-refresh-only',user:{id:actor,email:'test@example.test',aud:'authenticated',role:'authenticated'}}}))
 page.on('dialog',d=>d.accept())
 await page.goto('http://127.0.0.1:4593/cashier');await page.getByLabel('Email',{exact:true}).fill('test@example.test');await page.getByLabel('Password',{exact:true}).fill('test-password-only');await page.getByRole('button',{name:'Login kasir'}).click()
 const card=page.getByRole('article').filter({hasText:order.order_number+' ·'})
 await card.getByRole('button',{name:'Cek menu / revisi sebelum bayar'}).waitFor()
 assert.equal(await card.getByRole('button',{name:'Konfirmasi tunai lunas'}).count(),0)
 await card.getByRole('button',{name:'Cek menu / revisi sebelum bayar'}).click()
 await page.getByLabel('Jumlah',{exact:true}).fill('2')
 await page.getByRole('button',{name:'Menu tersedia dan pelanggan setuju — Simpan'}).click()
 await card.getByRole('button',{name:'Konfirmasi tunai lunas'}).waitFor()
 assert.equal(sql(`select total from public.orders where id='${order.id}'`),'24000')
 await card.getByRole('button',{name:'Konfirmasi tunai lunas'}).click()
 await card.getByRole('button',{name:'Semua item sudah diantar — Selesai'}).click()
 await page.getByRole('button',{name:'Riwayat',exact:true}).click()
 await page.getByText(order.order_number,{exact:false}).waitFor()
 const old=await create('expired');sql(`update public.orders set created_at=clock_timestamp()-interval '16 minutes' where id='${old.id}'`)
 await page.evaluate(({id,token})=>sessionStorage.setItem('tkm-order-'+id,token),{id:old.id,token:actor+actor})
 await page.goto('http://127.0.0.1:4593/order/'+old.id)
 await page.getByRole('button',{name:'Pesan ulang',exact:true}).click();await page.waitForURL('**/cart')
 await page.getByText('Browser Coffee',{exact:true}).waitFor()
 assert.equal(sql(`select status from public.orders where id='${old.id}'`),'expired')
 await page.getByRole('button',{name:'Pesan Sekarang',exact:true}).click();await page.waitForURL('**/order/*')
 const newID=page.url().split('/').pop();assert.notEqual(newID,old.id)
 assert.equal(sql(`select status from public.orders where id='${old.id}'`),'expired')
 assert.equal(sql(`select status from public.orders where id='${newID}'`),'pending')
 await page.goto('http://127.0.0.1:4593/cashier');await page.getByRole('button',{name:'Riwayat',exact:true}).click()
 await page.getByRole('article').filter({hasText:old.order_number+' ·'}).getByRole('button',{name:'Buat ulang pesanan',exact:true}).click()
 await page.getByRole('button',{name:'Menu tersedia dan pelanggan setuju — Simpan'}).click()
 await page.getByRole('heading',{name:/Periksa/}).waitFor()
 assert.equal(sql(`select count(*) from public.orders where id in(select order_id from public.order_items where product_id='${prod}')`),'4')
 assert.deepEqual(errors,[])
 console.log('PASS Chromium: review gate, quantity revision/server total, paid -> complete/history, expired -> customer reorder cart; real local Go/Postgres, mock Auth')
}finally{
 if(browser)await browser.close();for(const p of children)p.kill('SIGTERM');auth.close()
 sql(`delete from tkm.checkout_keys where order_id in(select id from public.orders where id in(select order_id from public.order_items where product_id='${prod}'));delete from tkm.outbox_events where order_id in(select id from public.orders where id in(select order_id from public.order_items where product_id='${prod}'));delete from public.payments where order_id in(select id from public.orders where id in(select order_id from public.order_items where product_id='${prod}'));delete from public.orders where id in(select order_id from public.order_items where product_id='${prod}');delete from public.tables where qr_token='${table}';delete from public.products where id='${prod}';delete from public.categories where id='${cat}';delete from public.profiles where id='${actor}';`)
}
