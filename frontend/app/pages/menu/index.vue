<script setup lang="ts">
import { groupProducts } from '#shared/product-selection'
definePageMeta({ layout: 'customer' })
const { menu, loading, load } = useMenu()
const { lines } = useCart()
const error = ref('')
const search = ref('')
const searchOpen = ref(false)
const drawerOpen = ref(false)
const searchInput = ref<HTMLInputElement | null>(null)
const activeCategory = ref('')
const catalog = ref<HTMLElement | null>(null)
const navRef = ref<HTMLElement | null>(null)
let observer: IntersectionObserver | null = null
let mounted = false
let observerGeneration = 0
const grouped = computed(() => groupProducts(menu.value?.categories ?? [], menu.value?.products ?? [], search.value))
const brand = computed(() => menu.value?.settings.brand_name || 'TerasKayuManis')
const itemCount = computed(() => lines.value.reduce((sum, line) => sum + line.qty, 0))
const cartTotal = computed(() => lines.value.reduce((sum, line) => sum + linePrice(line, menu.value?.products.find(p => p.id === line.productId)) * line.qty, 0))
useHead(() => ({ title: `Menu · ${brand.value}` }))
async function refresh() {
  error.value = ''
  try { await load(true) } catch { error.value = 'Menu belum dapat dimuat. Periksa koneksi dan coba lagi.' }
}
onMounted(async () => { mounted = true; await refresh(); await setupScrollSpy() })
onBeforeUnmount(() => { mounted = false; observerGeneration++; observer?.disconnect() })
async function setupScrollSpy() {
  const generation = ++observerGeneration
  observer?.disconnect()
  await nextTick()
  if (!mounted || generation !== observerGeneration) return
  activeCategory.value = grouped.value[0]?.category.id ?? ''
  const visible = new Map<string, Element>()
  observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (entry.isIntersecting) visible.set(entry.target.id, entry.target)
      else visible.delete(entry.target.id)
    }
    const first = [...visible.values()].sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top)[0]
    if (first) activeCategory.value = first.id.slice(4)
  }, { rootMargin: '-145px 0px -45% 0px', threshold: 0 })
  catalog.value?.querySelectorAll('[id^="cat-"]').forEach(el => observer?.observe(el))
}
watch(grouped, setupScrollSpy, { flush: 'post' })
watch(activeCategory, async id => {
  await nextTick()
  const chip = [...(navRef.value?.querySelectorAll<HTMLElement>('[data-category]') ?? [])].find(el => el.dataset.category === id)
  if (chip && navRef.value) navRef.value.scrollTo({ left: chip.offsetLeft - navRef.value.offsetLeft - 12, behavior: 'auto' })
})
async function toggleSearch() {
  searchOpen.value = !searchOpen.value
  if (!searchOpen.value) search.value = ''
  else { await nextTick(); searchInput.value?.focus() }
}
async function scrollToCategory(id: string) {
  drawerOpen.value = false
  await nextTick()
  activeCategory.value = id
  document.getElementById(`cat-${id}`)?.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' })
}
</script>

<template>
  <main ref="catalog" class="customer-shell customer-catalog">
    <header class="customer-header">
      <NuxtLink to="/" class="customer-icon" aria-label="Kembali ke beranda"><Icon name="arrow-left" /></NuxtLink>
      <h1>{{ brand }}</h1>
      <NuxtLink to="/cart" class="customer-icon customer-bag" aria-label="Keranjang"><Icon name="bag" /><span v-if="itemCount">{{ itemCount }}</span></NuxtLink>
    </header>
    <section class="customer-banner" aria-label="Informasi pemesanan">
      <div><p class="customer-eyebrow">PILIH. PESAN. NIKMATI.</p><h2>Selera kamu, pilihan kamu.</h2><p>Pesan di sini · Bayar tunai di kasir</p></div>
      <img class="customer-banner-logo" src="/images/restaurant-logo.webp" alt="Logo Teras Kayu Manis" width="80" height="80">
    </section>
    <div class="customer-category-bar">
      <div class="customer-category-tools">
        <button class="customer-icon customer-category-trigger" aria-label="Buka kategori" @click="drawerOpen = true"><Icon name="menu" :size="20" /><span>Kategori</span></button>
        <nav ref="navRef" class="customer-chips" aria-label="Kategori">
          <button v-for="g in grouped" :key="g.category.id" :data-category="g.category.id" class="customer-chip" :class="{ active: activeCategory === g.category.id }" :aria-pressed="activeCategory === g.category.id" @click="scrollToCategory(g.category.id)">{{ g.category.name }}</button>
        </nav>
        <button class="customer-icon" :aria-label="searchOpen ? 'Tutup pencarian' : 'Cari menu'" :aria-expanded="searchOpen" @click="toggleSearch"><Icon :name="searchOpen ? 'x' : 'search'" /></button>
      </div>
      <div v-if="searchOpen" class="customer-search"><label class="customer-sr-only" for="menu-search">Cari menu</label><input id="menu-search" ref="searchInput" v-model="search" type="search" placeholder="Cari menu favoritmu..."></div>
    </div>
    <div v-if="error" class="customer-state" role="alert"><p>{{ error }}</p><button class="customer-button" :disabled="loading" @click="refresh">Coba lagi</button></div>
    <p v-if="loading && !menu" class="customer-state" role="status">Memuat menu…</p>
    <template v-else-if="menu">
      <section v-for="g in grouped" :id="`cat-${g.category.id}`" :key="g.category.id" class="customer-category">
        <h2>{{ g.category.name }}</h2>
        <ul class="customer-product-list">
          <li v-for="p in g.products" :key="p.id" class="customer-product-row" :class="{ unavailable: !p.is_available }">
            <NuxtLink :to="`/menu/${p.id}`" class="customer-product-link">
              <CustomerImage :src="p.image_url" :alt="p.name" />
              <div class="customer-product-copy">
                <span v-if="p.is_best_seller || p.is_new" class="customer-product-badge">{{ p.is_best_seller ? 'Paling laris' : 'Baru' }}</span>
                <h3>{{ p.name }}</h3><p v-if="p.description" class="customer-description">{{ p.description }}</p>
                <strong>{{ fmtIDR(p.price) }}</strong><span v-if="!p.is_available" class="customer-small">Tidak tersedia</span>
              </div>
            </NuxtLink>
            <NuxtLink v-if="p.is_available" :to="`/menu/${p.id}`" class="customer-plus" :aria-label="`Tambah ${p.name}`"><Icon name="plus" /></NuxtLink>
          </li>
        </ul>
      </section>
      <div v-if="!grouped.length" class="customer-state" role="status"><h2>{{ search ? 'Menu tidak ditemukan' : 'Menu belum tersedia' }}</h2><p>{{ search ? 'Coba kata kunci lain.' : 'Silakan coba lagi nanti.' }}</p><button v-if="search" class="customer-text-button" @click="search = ''">Hapus pencarian</button></div>
    </template>
    <NuxtLink v-if="itemCount" to="/cart" class="customer-cart-bar"><span>{{ itemCount }} item · Lihat Pesanan</span><strong>{{ fmtIDR(cartTotal) }}</strong></NuxtLink>
    <CustomerModal :open="drawerOpen" title="Pilih Kategori" @close="drawerOpen = false">
      <nav class="customer-category-drawer" aria-label="Semua kategori"><button v-for="g in grouped" :key="g.category.id" class="customer-drawer-link" :aria-pressed="activeCategory === g.category.id" @click="scrollToCategory(g.category.id)">{{ g.category.name }}<span>{{ g.products.length }}</span></button></nav>
      <p v-if="!grouped.length" class="customer-muted">Tidak ada kategori untuk pencarian ini.</p>
    </CustomerModal>
  </main>
</template>
