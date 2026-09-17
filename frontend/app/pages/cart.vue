<script setup lang="ts">
import { prepareReorder, isCheckoutRejected } from '#shared/order-flow'
import type { CreateOrderPayload } from '#shared/types'

const { menu, load } = useMenu()
const { lines, remove, setQty, clear } = useCart()

const name = ref('')
const payment = ref<'cash'>('cash')
const submitting = ref(false)
const error = ref('')
const pendingCheckout = ref(false)
const catalogReady = ref(false)
const refreshing = ref(false)

async function loadCart() {
  if(refreshing.value)return
  refreshing.value=true;catalogReady.value=false
  try {
  const saved=sessionStorage.getItem('tkm-reorder')
  // An unresolved checkout takes priority over importing a different order.
  if(saved&&!pendingCheckout.value){
      const draft=JSON.parse(saved) as CreateOrderPayload
      await load(true)
      name.value=draft.customer_name
      const prepared=prepareReorder(draft,menu.value?.products??[])
      lines.value=prepared.lines
      sessionStorage.removeItem('tkm-reorder')
      error.value=prepared.errors.length?prepared.errors.join(' '):'Pesanan lama masuk keranjang. Periksa harga terbaru lalu konfirmasi untuk membuat nomor baru.'
  }
  await load()
  catalogReady.value=true
  }catch{error.value='Menu atau draft pesanan ulang tidak bisa dimuat. Muat ulang harga sebelum memesan.'}
  finally{refreshing.value=false}
}
onMounted(async () => {
  pendingCheckout.value=!!sessionStorage.getItem('tkm-checkout')
  await loadCart()
})

const productOf = (id: string) => menu.value?.products.find((p) => p.id === id)

const subtotal = computed(() =>
  lines.value.reduce((s, line) => s + linePrice(line, productOf(line.productId)) * line.qty, 0)
)
const service = computed(() => Math.round(subtotal.value * (Number(menu.value?.settings.service_pct) || 0) / 100))
const tax = computed(() => Math.round(subtotal.value * (Number(menu.value?.settings.tax_pct) || 0) / 100))
const total = computed(() => subtotal.value + service.value + tax.value)

async function placeOrder() {
  if (submitting.value) return
  error.value = ''
  submitting.value = true
  try {
    // Recovery uses the original identity and payload, even if the cart, table,
    // name or catalog changed. Never validate or create a NEW attempt first.
    let pending = JSON.parse(sessionStorage.getItem('tkm-checkout') || 'null') as { body: string; key: string; token: string } | null
    if (!pending) {
    if (!catalogReady.value || sessionStorage.getItem('tkm-reorder')) {
      error.value = 'Muat ulang harga dan periksa pesanan ulang sebelum memesan.'
      return
    }
    if (menu.value?.settings.require_customer_name && !name.value.trim()) {
      error.value = 'Mohon isi nama Anda.'
      return
    }
    const payload: CreateOrderPayload = {
      customer_name: name.value.trim(),
      payment_method: payment.value,
      items: lines.value.map((l) => ({
        product_id: l.productId,
        variant_ids: l.variantIds,
        addon_ids: l.addonIds,
        quantity: l.qty,
        notes: l.notes
      }))
    }
    const validation=prepareReorder(payload,menu.value?.products??[])
    if(!payload.items.length||validation.errors.length){error.value=validation.errors.join(' ')||'Keranjang kosong.';return}
    pending = { body: JSON.stringify(payload), key: crypto.randomUUID(), token: crypto.randomUUID() + crypto.randomUUID() }
    sessionStorage.setItem('tkm-checkout', JSON.stringify(pending))
    }
    pendingCheckout.value = true
    const res = await $fetch<{ id: string }>('/api/core/orders', { method: 'POST', body: JSON.parse(pending.body), headers: { 'Idempotency-Key': pending.key, 'X-Order-Token': pending.token } })
    sessionStorage.setItem('tkm-order-' + res.id, pending.token)
    sessionStorage.removeItem('tkm-checkout')
    pendingCheckout.value = false
    clear()
    await navigateTo(`/order/${res.id}`)
  } catch (e: unknown) {
    if(isCheckoutRejected(e)){
      sessionStorage.removeItem('tkm-checkout')
      pendingCheckout.value=false
      error.value='Pesanan ditolak dan tidak dibuat. Perbaiki keranjang sebelum memesan lagi.'
      return
    }
    error.value = (e as { data?: { statusMessage?: string }, message?: string })?.data?.statusMessage
      ?? (e as { message?: string })?.message
      ?? 'Gagal membuat pesanan. Coba lagi.'
    // Retain the attempt on ambiguous responses; retry must use the same key.
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 pb-32 pt-5">
    <div class="mb-5 flex items-center gap-3">
      <NuxtLink to="/menu" class="btn btn-ghost btn-sm" aria-label="Kembali ke menu"><Icon name="arrow-left" :size="18" /></NuxtLink>
      <h1 class="font-display text-2xl font-semibold">Keranjang</h1>
    </div>

    <div v-if="error" class="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700" role="alert">{{ error }}</div>
    <div v-if="pendingCheckout" class="card mb-4 p-4">
      <p>Checkout sebelumnya belum pasti. Coba ulang pengiriman yang sama; perubahan keranjang tidak dikirim dan tidak membuat pesanan baru.</p>
      <button class="btn btn-primary" :disabled="submitting" @click="placeOrder">Coba ulang pengiriman</button>
    </div>
    <div v-if="!catalogReady">
      <p>Harga belum diperbarui. Muat ulang sebelum mengonfirmasi pesanan.</p>
      <button class="btn" :disabled="refreshing||submitting" @click="loadCart">Muat ulang harga</button>
    </div>
    <div v-else-if="!lines.length" class="py-20 text-center">
      <Icon name="bag" :size="40" class="mx-auto text-brand-300" />
      <p class="mt-3 font-display text-lg text-brand-800">Keranjang Anda masih kosong</p>
      <NuxtLink to="/menu" class="btn btn-primary mt-4">Lihat Menu</NuxtLink>
    </div>

    <template v-else>

      <ul class="space-y-3">
        <li v-for="line in lines" :key="line.key" class="card p-4">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="font-semibold">{{ productOf(line.productId)?.name ?? 'Menu tidak tersedia' }}</p>
              <p v-if="line.variantIds.length" class="text-xs text-brand-500">
                {{ line.variantIds.map((id) => productOf(line.productId)?.variants.find((v) => v.id === id)?.name).filter(Boolean).join(' · ') }}
              </p>
              <p v-if="line.addonIds.length" class="text-xs text-brand-500">
                + {{ line.addonIds.map((id) => productOf(line.productId)?.addons.find((a) => a.id === id)?.name).filter(Boolean).join(', ') }}
              </p>
              <p v-if="line.notes" class="mt-0.5 text-xs italic text-brand-400">"{{ line.notes }}"</p>
            </div>
            <button class="btn btn-ghost btn-sm" :aria-label="`Hapus ${productOf(line.productId)?.name}`" @click="remove(line.key)">
              <Icon name="trash" :size="16" />
            </button>
          </div>
          <div class="mt-3 flex items-center justify-between">
            <div class="flex items-center gap-3 rounded-xl border border-brand-200 px-2.5">
              <button class="py-2 text-brand-600" :aria-label="`Kurangi ${productOf(line.productId)?.name}`" @click="setQty(line.key, line.qty - 1)"><Icon name="minus" :size="14" /></button>
              <span class="w-5 text-center text-sm font-semibold">{{ line.qty }}</span>
              <button class="py-2 text-brand-800" :aria-label="`Tambah ${productOf(line.productId)?.name}`" @click="setQty(line.key, line.qty + 1)"><Icon name="plus" :size="14" /></button>
            </div>
            <span class="font-semibold text-brand-800">{{ fmtIDR(linePrice(line, productOf(line.productId)) * line.qty) }}</span>
          </div>
        </li>
      </ul>

      <div class="card mt-4 p-4 text-sm">
        <div class="flex justify-between py-1"><span class="text-brand-500">Subtotal</span><span>{{ fmtIDR(subtotal) }}</span></div>
        <div v-if="service" class="flex justify-between py-1"><span class="text-brand-500">Service ({{ menu?.settings.service_pct }}%)</span><span>{{ fmtIDR(service) }}</span></div>
        <div v-if="tax" class="flex justify-between py-1"><span class="text-brand-500">Pajak ({{ menu?.settings.tax_pct }}%)</span><span>{{ fmtIDR(tax) }}</span></div>
        <div class="mt-2 flex justify-between border-t border-brand-100 pt-3 text-base font-bold"><span>Total</span><span>{{ fmtIDR(total) }}</span></div>
      </div>

      <div class="card mt-4 p-4">
        <p class="label">Tunai di kasir</p>
        <p class="text-sm">Setelah memesan, tunjukkan nomor order dan bayar tunai di kasir. Pesanan diproses setelah kasir mengonfirmasi lunas, lalu diantar ke meja.</p>

        <div class="mt-4">
          <label class="label" for="cust-name">Nama {{ menu?.settings.require_customer_name ? '' : '(opsional)' }}</label>
          <input id="cust-name" v-model="name" class="input" placeholder="Nama Anda" maxlength="100">
        </div>
      </div>

      <div class="fixed inset-x-0 bottom-0 border-t border-brand-100 bg-cream/95 p-4 backdrop-blur">
        <div class="mx-auto flex max-w-2xl items-center gap-3">
          <div class="flex-1">
            <p class="text-xs text-brand-500">
              Pesanan Anda
            </p>
            <p class="text-lg font-bold">{{ fmtIDR(total) }}</p>
          </div>
          <button class="btn btn-accent px-8" :disabled="submitting||pendingCheckout" @click="placeOrder">
            {{ submitting ? 'Memproses...' : pendingCheckout ? 'Selesaikan checkout sebelumnya' : 'Pesan Sekarang' }}
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
