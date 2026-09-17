<script setup lang="ts">
import { remainingSeconds } from '#shared/order-flow'
import type { CreateOrderPayload, Order, OrderStatus } from '#shared/types'
import type { RealtimeStatus } from '#shared/realtime'

const route = useRoute()
const order = ref<Order | null>(null)
const loadError = ref('')
const reorderError=ref(''),reordering=ref(false),now=ref(Date.now())
async function reorder(){
 if(reordering.value)return;reordering.value=true;reorderError.value=''
 try{
 if(sessionStorage.getItem('tkm-checkout')){reorderError.value='Selesaikan checkout sebelumnya yang belum pasti dahulu.';return}
 const payload=await $fetch<CreateOrderPayload>(`/api/core/orders/${route.params.uuid}/reorder`,{headers:{'X-Order-Token':sessionStorage.getItem('tkm-order-'+route.params.uuid)||''}})
 if(!confirm('Isi keranjang akan diganti pesanan lama. Harga dan menu diperiksa ulang; belum membuat order baru.'))return
 sessionStorage.setItem('tkm-reorder',JSON.stringify(payload))
 await navigateTo('/cart')
 }catch{reorderError.value='Pesanan ulang gagal disiapkan. Coba lagi atau hubungi kasir.'}finally{reordering.value=false}
}

const STEPS: { key: OrderStatus; label: string }[] = [
  { key: 'pending', label: 'Bayar di kasir' },
  { key: 'confirmed', label: 'Lunas / diproses' },
  { key: 'completed', label: 'Selesai' }
]

const realtimeStatus=ref<RealtimeStatus>('polling')
const realtimeLabel=computed(()=>realtimeStatus.value==='connected'?'Realtime tersambung':realtimeStatus.value==='connecting'?'Menghubungkan…':'Polling cadangan')
let realtime:ReturnType<typeof useRealtime<Order>>|undefined
let mounted=false
function trackOrder(){
 realtime?.dispose();realtime=undefined
 order.value=null;loadError.value='';reorderError.value=''
 if(!mounted)return
 const id=String(route.params.uuid)
 realtime=useRealtime<Order>({scope:{channel:'order',order_id:id},
  subscribe:async()=>{const token=sessionStorage.getItem('tkm-order-'+id);return token?{type:'subscribe',channel:'order',order_id:id,order_token:token}:null},
  fetchSnapshot:({signal})=>$fetch<Order>(`/api/core/orders/${id}`,{signal,headers:{'X-Order-Token':sessionStorage.getItem('tkm-order-'+id)||''}}),
  apply:snapshot=>{
   if(String(route.params.uuid)!==id||snapshot.id!==id)return
   if(!order.value||snapshot.version>=order.value.version)order.value=snapshot
   loadError.value=''
  },
  onStatus:value=>realtimeStatus.value=value,
  onError:()=>{loadError.value='Pesanan tidak dapat dimuat. Periksa koneksi atau hubungi kasir.'}
 })
 realtime.start()
}
watch(()=>route.params.uuid,trackOrder,{flush:'sync'})
onMounted(()=>{mounted=true;trackOrder()})
// Server status remains authoritative; local clock only displays remaining time.
let clock:ReturnType<typeof setInterval>|undefined
onMounted(()=>{clock=setInterval(()=>now.value=Date.now(),1000)})
onUnmounted(() => {mounted=false;realtime?.dispose();clearInterval(clock)})

const stepIndex = computed(() => STEPS.findIndex((s) => s.key === order.value?.status))
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 pb-10 pt-6">
    <p role="status" aria-live="polite">{{realtimeLabel}}</p>
    <div v-if="loadError" class="py-20 text-center">
      <p class="font-display text-lg text-brand-800">{{ loadError }}</p>
      <NuxtLink to="/menu" class="btn btn-primary mt-4">Kembali ke Menu</NuxtLink>
    </div>

    <template v-else-if="order">
      <div class="mb-6 text-center">
        <p class="text-sm text-brand-500">Nomor Pesanan</p>
        <p class="font-display text-4xl font-bold text-brand-950">{{ order.order_number }}</p>
        <p v-if="order.customer_name" class="mt-1 text-sm text-brand-500">{{ order.customer_name }}</p>
      </div>

      <div v-if="order.status === 'cancelled'" class="mb-6 rounded-2xl bg-red-50 p-5 text-center text-red-700">
        <p class="font-semibold">Pesanan dibatalkan</p>
        <p class="text-sm">Silakan hubungi staf kami untuk info lebih lanjut.</p>
      </div>

      <div v-else-if="order.status === 'expired'" class="mb-6 rounded-2xl bg-amber-50 p-5 text-center">
        <p class="font-semibold">Pesanan expired</p><p>Batas bayar 15 menit sudah lewat. Order lama tetap tersimpan.</p>
        <button class="btn btn-primary mt-3" :disabled="reordering" @click="reorder">Pesan ulang</button>
        <p v-if="reorderError" role="alert">{{reorderError}}</p>
      </div>
      <ol v-else class="mb-6 flex items-start">
        <li v-for="(step, i) in STEPS" :key="step.key" class="relative flex-1 text-center" :class="{ 'text-brand-900': i <= stepIndex, 'text-brand-300': i > stepIndex }">
          <div class="mx-auto flex size-9 items-center justify-center rounded-full border-2 transition"
            :class="i < stepIndex ? 'border-brand-800 bg-brand-800 text-cream' : i === stepIndex ? 'border-brand-800 text-brand-800' : 'border-brand-200'">
            <Icon v-if="i < stepIndex" name="check" :size="16" />
            <span v-else class="text-xs font-bold">{{ i + 1 }}</span>
          </div>
          <p class="mt-1.5 text-xs font-medium">{{ step.label }}</p>
          <div v-if="i < STEPS.length - 1" class="absolute left-1/2 top-4.5 hidden h-0.5 w-full" :class="i < stepIndex ? 'bg-brand-800' : 'bg-brand-200'" />
        </li>
      </ol>

      <p v-if="order.status==='pending'" class="mb-3">Sisa waktu bayar: {{remainingSeconds(order.expires_at,now)}} detik. Kasir mengecek ketersediaan dan menyepakati revisi sebelum menerima uang.</p>
      <div class="card mb-4 p-4">
        <div class="flex items-center justify-between">
          <span class="text-sm text-brand-500">Pembayaran</span>
          <span class="badge" :class="order.payment_status === 'paid' ? 'bg-emerald-100 text-emerald-700' : 'bg-brand-100 text-brand-700'">
            {{ order.payment_status === 'paid' ? 'Lunas' : 'Belum dibayar' }}
          </span>
        </div>
        <div class="mt-1 flex items-center justify-between text-sm">
          <span class="text-brand-500">Metode</span>
          <span class="font-medium">Tunai di kasir</span>
        </div>
        <p v-if="order.status === 'pending'" class="mt-2 text-xs text-brand-500">
          Tunjukkan nomor pesanan ini dan bayar tunai di kasir. Pesanan belum diproses sebelum pembayaran dikonfirmasi.
        </p>
      </div>

      <div class="card p-4">
        <ul class="divide-y divide-brand-50">
          <li v-for="item in order.order_items" :key="item.id" class="py-3">
            <div class="flex justify-between gap-3">
              <div>
                <p class="font-medium">{{ item.quantity }}x {{ item.product_name }}</p>
                <p v-if="item.variant_name" class="text-xs text-brand-500">{{ item.variant_name }}</p>
                <p v-for="a in item.order_item_addons" :key="a.addon_name" class="text-xs text-brand-500">+ {{ a.addon_name }}</p>
                <p v-if="item.notes" class="text-xs italic text-brand-400">"{{ item.notes }}"</p>
              </div>
              <span class="shrink-0 font-medium">{{ fmtIDR(item.subtotal) }}</span>
            </div>
          </li>
        </ul>
        <div class="space-y-1 border-t border-brand-100 pt-3 text-sm">
          <div class="flex justify-between"><span class="text-brand-500">Subtotal</span><span>{{ fmtIDR(order.subtotal) }}</span></div>
          <div v-if="order.service_charge" class="flex justify-between"><span class="text-brand-500">Service</span><span>{{ fmtIDR(order.service_charge) }}</span></div>
          <div v-if="order.tax" class="flex justify-between"><span class="text-brand-500">Pajak</span><span>{{ fmtIDR(order.tax) }}</span></div>
          <div class="flex justify-between pt-1 text-base font-bold"><span>Total</span><span>{{ fmtIDR(order.total) }}</span></div>
        </div>
      </div>

      <NuxtLink to="/menu" class="btn btn-outline mt-5 w-full">Pesan Lagi</NuxtLink>
    </template>
  </div>
</template>
