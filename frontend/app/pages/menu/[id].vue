<script setup lang="ts">
import { defaultSelection, validateSelection, selectionPrice, variantGroups, recommendations } from '#shared/product-selection'
import type { ProductSelection } from '#shared/product-selection'
definePageMeta({ layout: 'customer' })
const route = useRoute()
const { menu, loading, load } = useMenu()
const { add } = useCart()
const error = ref('')
const ready = ref(false)
const submitting = ref(false)
const product = computed(() => menu.value?.products.find(p => p.id === String(route.params.id)))
const selection = ref<ProductSelection>({ variantIds: [], addonIds: [], qty: 1, notes: '' })
const groups = computed(() => product.value ? variantGroups(product.value) : [])
const suggested = computed(() => recommendations(menu.value?.products ?? [], String(route.params.id)))
const errors = computed(() => product.value ? validateSelection(product.value, selection.value) : [])
const total = computed(() => product.value ? selectionPrice(product.value, selection.value) * selection.value.qty : 0)
useHead(() => ({ title: `${product.value?.name ?? 'Detail menu'} · ${menu.value?.settings.brand_name || 'TerasKayuManis'}` }))
let refreshGeneration = 0
let selectionRoute: string | undefined
async function refresh() {
  const generation = ++refreshGeneration
  const routeId = String(route.params.id)
  error.value = ''; ready.value = false
  try {
    await load(true)
    if (generation !== refreshGeneration || routeId !== String(route.params.id)) return
    if (product.value && selectionRoute !== routeId) {
      selection.value = defaultSelection(product.value)
      selectionRoute = routeId
    }
    ready.value = true
  } catch {
    if (generation === refreshGeneration && routeId === String(route.params.id)) error.value = 'Detail menu belum dapat dimuat. Coba lagi.'
  }
}
onMounted(refresh)
watch(() => route.params.id, () => { selectionRoute = undefined; refresh() }, { flush: 'sync' })
onUnmounted(() => { ++refreshGeneration })
function choose(group: string, id: string) {
  const groupIds = groups.value.find(([name]) => name === group)?.[1].map(v => v.id) ?? []
  selection.value.variantIds = [...selection.value.variantIds.filter(v => !groupIds.includes(v)), id]
}
async function submit() {
  if (!product.value || !ready.value || submitting.value) return
  const invalid = validateSelection(product.value, selection.value)
  if (invalid.length) { error.value = invalid.join(' '); return }
  submitting.value = true
  add({ productId: product.value.id, ...selection.value, variantIds: [...selection.value.variantIds], addonIds: [...selection.value.addonIds] })
  await navigateTo('/menu')
  submitting.value = false
}
</script>

<template>
  <main class="customer-shell customer-detail">
    <header class="customer-header"><NuxtLink to="/menu" class="customer-icon" aria-label="Kembali ke menu"><Icon name="arrow-left" /></NuxtLink><span>Detail Menu</span><NuxtLink to="/cart" class="customer-icon" aria-label="Keranjang"><Icon name="bag" /></NuxtLink></header>
    <div v-if="error" class="customer-state" role="alert"><p>{{ error }}</p><button class="customer-button" :disabled="loading" @click="refresh">Muat ulang menu</button></div>
    <p v-if="!ready && !error" class="customer-state" role="status">Memuat detail menu…</p>
    <template v-if="product && ready">
      <CustomerImage class="customer-detail-image" :src="product.image_url" :alt="product.name" eager />
      <section class="customer-detail-intro"><h1>{{ product.name }}</h1><strong class="customer-detail-price">{{ fmtIDR(product.price) }}</strong><p v-if="product.description" class="customer-muted">{{ product.description }}</p><p v-if="!product.is_available" role="status">Menu ini sedang tidak tersedia.</p></section>
      <section v-if="suggested.length" class="customer-recommendations"><h2>Rekomendasi</h2><div class="customer-recommendation-strip"><NuxtLink v-for="p in suggested" :key="p.id" :to="`/menu/${p.id}`"><CustomerImage :src="p.image_url" :alt="p.name" /><h3>{{ p.name }}</h3><p>{{ fmtIDR(p.price) }}</p></NuxtLink></div></section>
      <form id="product-selection" class="customer-selection" @submit.prevent="submit">
        <fieldset v-for="[group, variants] in groups" :key="group"><legend>{{ group }} <span>{{ variants.some(v => v.is_available) ? 'Pilih satu' : 'Tidak tersedia' }}</span></legend>
          <label v-for="v in variants" :key="v.id" class="customer-option" :class="{ unavailable: !v.is_available }"><span><input type="radio" :name="group" :value="v.id" :checked="selection.variantIds.includes(v.id)" :disabled="!v.is_available" @change="choose(group, v.id)">{{ v.name }}<small v-if="!v.is_available">Tidak tersedia</small></span><span>{{ v.price_modifier > 0 ? '+' : '' }}{{ fmtIDR(v.price_modifier) }}</span></label>
        </fieldset>
        <fieldset v-if="product.addons.length"><legend>Tambahan <span>Opsional</span></legend><label v-for="a in product.addons" :key="a.id" class="customer-option" :class="{ unavailable: !a.is_available }"><span><input v-model="selection.addonIds" type="checkbox" :value="a.id" :disabled="!a.is_available">{{ a.name }}<small v-if="!a.is_available">Tidak tersedia</small></span><span>+{{ fmtIDR(a.price) }}</span></label></fieldset>
        <div class="customer-notes"><label for="product-notes">Catatan <span>Opsional</span></label><textarea id="product-notes" v-model="selection.notes" maxlength="200" rows="3" placeholder="Contoh: tidak pedas" /><p class="customer-small customer-muted">{{ selection.notes.length }}/200 karakter</p></div>
        <p class="customer-small customer-muted">Harga dan ketersediaan diperiksa kembali saat memesan.</p>
        <ul v-if="errors.length" class="customer-validation" aria-live="polite"><li v-for="message in errors" :key="message">{{ message }}</li></ul>
      </form>
      <footer class="customer-detail-footer"><div class="customer-quantity"><button type="button" aria-label="Kurangi jumlah" :disabled="selection.qty <= 1" @click="selection.qty = Math.max(1, selection.qty - 1)"><Icon name="minus" :size="18" /></button><output aria-live="polite" aria-label="Jumlah">{{ selection.qty }}</output><button type="button" aria-label="Tambah jumlah" :disabled="selection.qty >= 50" @click="selection.qty = Math.min(50, selection.qty + 1)"><Icon name="plus" :size="18" /></button></div><button form="product-selection" type="submit" class="customer-button" :disabled="!ready || !!errors.length || submitting"><span>Tambah ke Keranjang<small>{{ fmtIDR(total) }}</small></span></button></footer>
    </template>
    <div v-else-if="ready" class="customer-state"><h1>Menu tidak ditemukan</h1><p>Menu mungkin sudah dihapus.</p><NuxtLink to="/menu" class="customer-button">Kembali ke Menu</NuxtLink></div>
  </main>
</template>
