<script setup lang="ts">
import type { Order, MenuResponse, CreateOrderPayload } from '#shared/types'
import { canAcceptCash, remainingSeconds, prepareReorder, isCheckoutRejected } from '#shared/order-flow'
import type { RealtimeStatus } from '#shared/realtime'
import type { AuthChangeEvent } from '@supabase/supabase-js'
const email=ref(''),password=ref(''),error=ref(''),busy=ref(false),loggedIn=ref(false)
const orders=ref<Order[]>([]),menu=ref<MenuResponse|null>(null)
const received=reactive<Record<string,number>>({})
const tab=ref<'active'|'history'>('active'),expiredOnly=ref(false),offset=ref(0),now=ref(Date.now())
const editing=ref<Order|null>(null),draft=ref<CreateOrderPayload|null>(null)
const draftIdentity=ref(0)
const client=useSupabase()
let generation=0
let realtime:ReturnType<typeof useRealtime<Order[]>>|undefined
let disposed=false
const realtimeStatus=ref<RealtimeStatus>('polling')
const realtimeLabel=computed(()=>realtimeStatus.value==='connected'?'Realtime tersambung':realtimeStatus.value==='connecting'?'Menghubungkan…':'Polling cadangan')
function applyOrders(data:Order[]){
 const previous=new Map(orders.value.map(o=>[o.id,o]))
 orders.value=data.map(o=>{const old=previous.get(o.id);return old&&old.version>o.version?old:o})
}
function startRealtime(){
 realtime?.dispose();realtime=undefined
 if(disposed||!loggedIn.value||typeof window==='undefined')return
 const query={tab:tab.value,status:tab.value==='history'&&expiredOnly.value?'expired':undefined,offset:offset.value,limit:100}
 realtime=useRealtime<Order[]>({scope:{channel:'cashier'},
  subscribe:async()=>{const {data}=await client.auth.getSession();return data.session?{type:'subscribe',channel:'cashier',access_token:data.session.access_token}:null},
  fetchSnapshot:async({signal})=>$fetch<Order[]>('/api/core/admin/orders',{signal,headers:await headers(),query}),
  apply:applyOrders,onStatus:value=>realtimeStatus.value=value,
  onError:()=>{error.value='Tidak dapat memuat pesanan. Periksa login, koneksi dan izin kasir.'}
 })
 realtime.setBusy(busy.value);realtime.start()
}
watch(busy,value=>realtime?.setBusy(value),{flush:'sync'})
watch([tab,expiredOnly,offset],()=>{generation++;startRealtime()})
async function headers(){
 const {data}=await client.auth.getSession();if(!data.session)throw new Error('Login diperlukan')
 return {Authorization:`Bearer ${data.session.access_token}`}
}
async function load(){
 if(disposed)return
 if(realtime){realtime.refresh();return}
 const seq=++generation
 try {
 const data=await $fetch<Order[]>('/api/core/admin/orders',{headers:await headers(),query:{tab:tab.value,status:tab.value==='history'&&expiredOnly.value?'expired':undefined,offset:offset.value,limit:100}})
 if(seq!==generation)return
 applyOrders(data);loggedIn.value=true;startRealtime()
 }catch{if(seq===generation)error.value='Tidak dapat memuat pesanan. Periksa login, koneksi dan izin kasir.'}
}
async function login(){busy.value=true;try{const {error:e}=await client.auth.signInWithPassword({email:email.value,password:password.value});if(e)throw e;password.value='';error.value='';await load()}catch{error.value='Login gagal.'}finally{busy.value=false}}
async function edit(o:Order){
 if(busy.value)return;busy.value=true;error.value=''
 try{menu.value=await $fetch<MenuResponse>('/api/core/menu');editing.value=JSON.parse(JSON.stringify(o));draft.value=null}catch{error.value='Menu gagal dimuat.'}finally{busy.value=false}
}
function initial(o:Order):CreateOrderPayload['items']{return (o.order_items??[]).map(i=>({product_id:i.product_id,quantity:i.quantity,variant_ids:i.variant_ids??[],addon_ids:i.addon_ids??[],notes:i.notes??''}))}
async function review(items:CreateOrderPayload['items']){
 const o=editing.value;if(!o||busy.value)return;busy.value=true;error.value=''
 try{
 const updated=await $fetch<Order>(`/api/core/orders/${o.id}/review`,{method:'POST',headers:await headers(),body:{expected_version:o.version,items}})
 received[updated.id]=updated.total;editing.value=null;await load()
 }catch{error.value='Review belum tersimpan atau versi berubah/waktu habis. Muat ulang dan periksa lagi sebelum menerima uang.';editing.value=null;await load()}finally{busy.value=false}
}
async function action(o:Order,kind:'confirm-cash'|'complete'){
 if(busy.value||editing.value||draft.value)return
 if(kind==='confirm-cash'&&!canAcceptCash(o,Date.now())){error.value='Periksa menu dahulu; order harus belum kedaluwarsa.';return}
 if(!confirm(kind==='complete'?'Semua item sudah diantar ke meja pelanggan?':`Menu sudah dicek dan pelanggan setuju total ${fmtIDR(o.total)}. Uang tunai sudah diterima?`))return
 busy.value=true;error.value=''
 try{
 const endpoint=kind==='complete'?`/api/core/orders/${o.id}/complete`:`/api/core/orders/${o.id}/confirm-cash`
 await $fetch(endpoint,{method:'POST',headers:await headers(),body:kind==='confirm-cash'?{received_rp:received[o.id]??o.total,expected_version:o.version}:{}})
 await load()
 }catch{error.value='Konfirmasi belum pasti atau order berubah/kedaluwarsa. Muat ulang sebelum mencoba lagi; jangan minta pembayaran ulang.';await load()}finally{busy.value=false}
}
async function reorder(o:Order){
 if(busy.value)return;busy.value=true;error.value=''
 try{
 if(sessionStorage.getItem('tkm-cashier-checkout')){error.value='Selesaikan percobaan pesanan ulang sebelumnya dahulu.';return}
 if(draft.value&&!confirm('Ganti draft pesanan ulang? Perubahan draft saat ini akan dibuang.'))return
 const [payload,catalog]=await Promise.all([$fetch<CreateOrderPayload>(`/api/core/orders/${o.id}/reorder`,{headers:await headers()}),$fetch<MenuResponse>('/api/core/menu')])
 menu.value=catalog;draft.value=payload;draftIdentity.value++;editing.value=null
 }catch{error.value='Tidak dapat menyiapkan pesanan ulang.'}finally{busy.value=false}
}
async function createAgain(items:CreateOrderPayload['items']){
 if(!draft.value||busy.value)return
 if(sessionStorage.getItem('tkm-cashier-checkout')){error.value='Masih ada pengiriman belum pasti. Gunakan Coba ulang pengiriman.';return}
 if(prepareReorder({...draft.value,items},menu.value?.products??[]).errors.length)return
 if(!confirm('Buat nomor order baru? Order lama tetap expired, pembayaran belum diterima.'))return
 const payload={...draft.value,items}
 const attempt={payload,key:crypto.randomUUID(),token:crypto.randomUUID()+crypto.randomUUID()}
 sessionStorage.setItem('tkm-cashier-checkout',JSON.stringify(attempt))
 await sendAttempt()
}
async function sendAttempt(){
 if(busy.value)return;busy.value=true;error.value=''
 try{
 const attempt=JSON.parse(sessionStorage.getItem('tkm-cashier-checkout')??'null');if(!attempt)return
 const result=await $fetch<Order>('/api/core/orders',{method:'POST',body:attempt.payload,headers:{'Idempotency-Key':attempt.key,'X-Order-Token':attempt.token}})
 sessionStorage.removeItem('tkm-cashier-checkout');draft.value=null;tab.value='active';offset.value=0;await load();await nextTick();editing.value=JSON.parse(JSON.stringify(result))
 }catch(e){
 if(isCheckoutRejected(e)){
 sessionStorage.removeItem('tkm-cashier-checkout')
 error.value='Pesanan ulang ditolak dan tidak dibuat. Perbaiki draft atau pilih pesanan ulang lagi.'
 }else{error.value='Pesanan ulang belum pasti. Gunakan Coba ulang pengiriman; jangan membuat percobaan baru.'}
 }finally{busy.value=false}
}
async function changeTab(value:'active'|'history'){if(busy.value)return;tab.value=value;offset.value=0;editing.value=null;draft.value=null;error.value='';await load()}
let clock:ReturnType<typeof setInterval>|undefined
let authSubscription:{unsubscribe:()=>void}|undefined
function clearSession(){generation++;realtime?.dispose();realtime=undefined;loggedIn.value=false;orders.value=[];editing.value=null;draft.value=null}
onMounted(async()=>{
 clock=setInterval(()=>now.value=Date.now(),1000)
 authSubscription=client.auth.onAuthStateChange?.((event:AuthChangeEvent)=>{
  if(event==='SIGNED_OUT')clearSession()
  else if(event==='TOKEN_REFRESHED')realtime?.reconnect()
 })?.data.subscription
 const seq=generation,{data}=await client.auth.getSession()
 if(disposed||seq!==generation)return
 if(data.session)await load()
})
onUnmounted(()=>{disposed=true;generation++;realtime?.dispose();authSubscription?.unsubscribe();clearInterval(clock)})
async function logout(){clearSession();await client.auth.signOut()}
</script>
<template>
 <main class="mx-auto max-w-4xl p-5">
  <h1 class="text-2xl font-bold">Kasir TerasKayuManis</h1>
  <p class="my-2">Cek menu dan sepakati revisi → terima tunai → konfirmasi lunas → setelah semua diantar, selesai.</p>
  <p v-if="error" role="alert" class="my-3 text-red-700">{{error}}</p>
  <form v-if="!loggedIn" class="grid gap-3 max-w-md" @submit.prevent="login">
   <label>Email<input v-model="email" type="email" autocomplete="username" required class="input"></label>
   <label>Password<input v-model="password" type="password" autocomplete="current-password" required class="input"></label>
   <button class="btn btn-primary" :disabled="busy">Login kasir</button>
  </form>
  <template v-else>
   <p role="status" aria-live="polite">{{realtimeLabel}}</p>
   <div class="flex flex-wrap gap-3 my-4">
    <button class="btn" :disabled="busy" :aria-pressed="tab==='active'" @click="changeTab('active')">Aktif</button>
    <button class="btn" :disabled="busy" :aria-pressed="tab==='history'" @click="changeTab('history')">Riwayat</button>
    <button class="btn" :disabled="busy" @click="load">Muat ulang</button><button class="btn" :disabled="busy" @click="logout">Keluar</button>
    <button class="btn" :disabled="busy" @click="sendAttempt">Coba ulang pengiriman</button>
   </div>
   <label v-if="tab==='history'"><input v-model="expiredOnly" type="checkbox" :disabled="busy" @change="offset=0;load()">Hanya Expired</label>
   <section v-if="draft&&menu" class="card p-3"><h2>Pesan ulang — nomor baru, timer baru</h2><OrderEditor :key="draftIdentity" :products="menu.products" :initial="draft.items" :disabled="busy" @save="createAgain"/><button class="btn" :disabled="busy" @click="draft=null">Tutup draft</button></section>
   <section v-if="editing&&menu" class="card p-3"><h2>Periksa {{editing.order_number}} · versi {{editing.version}}</h2><OrderEditor :key="editing.id+':'+editing.version" :products="menu.products" :initial="initial(editing)" :disabled="busy" @save="review"/><button class="btn" :disabled="busy" @click="editing=null">Tutup revisi</button></section>
   <article v-for="o in orders" :key="o.id" class="card my-3 p-4">
    <h2 class="font-bold">{{o.order_number}} · {{fmtIDR(o.total)}}</h2>
    <p>{{STATUS_LABEL[o.status]??o.status}} · {{o.payment_status}}</p>
    <p v-if="o.status==='pending'">Sisa waktu bayar: {{remainingSeconds(o.expires_at,now)}} detik. Revisi tidak memperpanjang waktu.</p>
    <ul class="my-3"><li v-for="i in o.order_items" :key="i.id">{{i.quantity}}× {{i.product_name}} {{i.variant_name}} <span v-if="i.notes">— {{i.notes}}</span><span v-for="a in i.order_item_addons" :key="a.addon_name"> + {{a.addon_name}}</span></li></ul>
    <template v-if="o.status==='pending'">
     <button class="btn" :disabled="busy||remainingSeconds(o.expires_at,now)===0" @click="edit(o)">Cek menu / revisi sebelum bayar</button>
     <template v-if="canAcceptCash(o,now)&&!editing&&!draft">
      <p>Menu sudah diperiksa. Total yang disepakati: {{fmtIDR(o.total)}}</p>
      <label>Uang diterima (Rp)<input v-model.number="received[o.id]" type="number" :min="o.total" :placeholder="String(o.total)" class="input"></label>
      <p>Kembalian: {{fmtIDR(Math.max(0,(received[o.id]??o.total)-o.total))}}</p>
      <button class="btn btn-primary" :disabled="busy" @click="action(o,'confirm-cash')">Konfirmasi tunai lunas</button>
     </template>
    </template>
    <button v-if="o.status==='expired'" class="btn" :disabled="busy" @click="reorder(o)">Buat ulang pesanan</button>
    <button v-if="o.status==='confirmed'&&o.payment_status==='paid'" class="btn btn-primary" :disabled="busy||!!editing||!!draft" @click="action(o,'complete')">Semua item sudah diantar — Selesai</button>
   </article>
   <p v-if="!orders.length">Tidak ada pesanan pada tab ini.</p>
   <button class="btn" :disabled="busy||offset===0" @click="offset=Math.max(0,offset-100);load()">Sebelumnya</button>
   <button class="btn" :disabled="busy||orders.length<100" @click="offset+=100;load()">Berikutnya</button>
  </template>
 </main>
</template>
