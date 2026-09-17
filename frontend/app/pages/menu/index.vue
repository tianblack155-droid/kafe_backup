<script setup lang="ts">
import type { Product } from '#shared/types'

const { menu, loading, load } = useMenu()
const { lines, add, setQty } = useCart()

const searchOpen = ref(false)
const search = ref('')
const selected = ref<Product | null>(null)
const activeCategory = ref('')
const navRef = ref<HTMLElement | null>(null)
let observer: IntersectionObserver | null = null

onMounted(async () => {
  await load()
  useHead({ title: menu.value?.settings.brand_name ?? 'TerasKayuManis' })
  await nextTick()
  setupScrollSpy()
})

onUnmounted(() => observer?.disconnect())

// ponytail: native IntersectionObserver for scroll-spy; no lib needed
function setupScrollSpy() {
  observer?.disconnect()
  observer = new IntersectionObserver(
    (entries) => {
      const visible = entries.filter((e) => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)
      if (visible[0]) activeCategory.value = visible[0].target.id.replace('cat-', '')
    },
    { rootMargin: '-160px 0px -60% 0px', threshold: 0 }
  )
  document.querySelectorAll('[id^="cat-"]').forEach((el) => observer!.observe(el))
}

const grouped = computed(() => {
  if (!menu.value) return []
  const q = search.value.trim().toLowerCase()
  return menu.value.categories
    .map((c) => ({
      category: c,
      products: menu.value!.products.filter(
        (p) => p.category_id === c.id && (!q || p.name.toLowerCase().includes(q) || (p.description ?? '').toLowerCase().includes(q))
      )
    }))
    .filter((g) => g.products.length)
})

const bestSellers = computed(() => menu.value?.products.filter((p) => p.is_best_seller && p.is_available) ?? [])
const itemCount = computed(() => lines.value.reduce((s, l) => s + l.qty, 0))
const cartTotal = computed(() =>
  lines.value.reduce((sum, line) => sum + linePrice(line, menu.value?.products.find((p) => p.id === line.productId)) * line.qty, 0)
)

// qty of a product in cart, only counting simple lines (no variant/addon/notes) so stepper is unambiguous
function simpleLine(p: Product) {
  return lines.value.find((l) => l.productId === p.id && !l.variantIds.length && !l.addonIds.length && !l.notes)
}
function cardQty(p: Product) {
  return lines.value.filter((l) => l.productId === p.id).reduce((s, l) => s + l.qty, 0)
}
function needsConfig(p: Product) {
  return p.variants.length > 0 || p.addons.length > 0
}

function quickAdd(p: Product) {
  if (needsConfig(p)) { selected.value = p; return }
  add({ productId: p.id, variantIds: [], addonIds: [], qty: 1, notes: '' })
}
function stepDown(p: Product) {
  const line = simpleLine(p)
  if (line) setQty(line.key, line.qty - 1)
}

function scrollTo(id: string) {
  document.getElementById(`cat-${id}`)?.scrollIntoView({ behavior: 'smooth' })
}

function badge(p: Product) {
  if (p.is_best_seller) return { text: 'Best Seller', class: 'bg-gold-500 text-brand-950' }
  if (p.is_new) return { text: 'Baru', class: 'bg-emerald-600 text-white' }
  if (p.is_featured) return { text: 'Rekomendasi', class: 'bg-brand-800 text-cream' }
  return null
}
</script>

<template>
  <div class="mx-auto max-w-2xl bg-white pb-28 shadow-sm">
    <header class="sticky top-0 z-30 border-b border-brand-100 bg-white/95 backdrop-blur">
      <div class="flex items-center justify-between gap-3 px-4 pb-3 pt-4">
        <div class="min-w-0">
          <h1 class="truncate font-display text-xl font-semibold text-brand-950">
            {{ menu?.settings.brand_name ?? 'TerasKayuManis' }}
          </h1>
          <p v-if="menu?.settings.tagline" class="truncate text-xs text-brand-500">{{ menu.settings.tagline }}</p>
        </div>
        <div class="flex shrink-0 items-center gap-1">
          <button class="btn btn-ghost btn-sm" :aria-label="searchOpen ? 'Tutup pencarian' : 'Cari menu'" @click="searchOpen = !searchOpen; if (!searchOpen) search = ''">
            <Icon :name="searchOpen ? 'x' : 'search'" :size="18" />
          </button>
          <NuxtLink to="/cart" class="btn btn-ghost btn-sm relative" aria-label="Keranjang">
            <Icon name="bag" :size="18" />
            <span v-if="itemCount" class="absolute -right-0.5 -top-0.5 flex size-4.5 items-center justify-center rounded-full bg-gold-500 text-[10px] font-bold text-brand-950">{{ itemCount }}</span>
          </NuxtLink>
        </div>
      </div>

      <div v-if="searchOpen" class="px-4 pb-3">
        <input v-model="search" type="search" placeholder="Cari menu..." class="input !h-10" autofocus>
      </div>

      <nav v-if="menu && !search" class="no-scrollbar flex gap-1.5 overflow-x-auto px-4 pb-2.5" aria-label="Kategori">
        <button
          v-for="g in grouped"
          :key="g.category.id"
          class="shrink-0 rounded-full px-3.5 py-1.5 text-sm font-medium transition"
          :class="activeCategory === g.category.id ? 'bg-brand-800 text-cream' : 'bg-brand-50 text-brand-700'"
          @click="scrollTo(g.category.id)"
        >
          {{ g.category.name }}
        </button>
      </nav>
    </header>

    <div v-if="loading && !menu" class="py-20 text-center text-brand-500">Memuat menu...</div>

    <template v-else-if="menu">
      <!-- Best seller strip -->
      <section v-if="bestSellers.length && !search" class="border-b border-brand-100 px-4 py-4">
        <h2 class="mb-3 font-display text-base font-semibold text-brand-900">⭐ Paling Laris</h2>
        <div class="no-scrollbar -mx-4 flex gap-3 overflow-x-auto px-4">
          <button v-for="p in bestSellers" :key="p.id" class="w-32 shrink-0 text-left" @click="selected = p">
            <div class="relative aspect-square overflow-hidden rounded-xl bg-brand-100">
              <img v-if="p.image_url" :src="p.image_url" :alt="p.name" loading="lazy" class="h-full w-full object-cover">
              <div v-else class="flex h-full w-full items-center justify-center font-display text-3xl text-brand-400">{{ p.name.charAt(0) }}</div>
            </div>
            <p class="mt-1.5 truncate text-sm font-medium">{{ p.name }}</p>
            <p class="text-xs font-semibold text-brand-700">{{ fmtIDR(p.price) }}</p>
          </button>
        </div>
      </section>

      <!-- Category sections, list layout -->
      <section v-for="g in grouped" :id="`cat-${g.category.id}`" :key="g.category.id" class="scroll-mt-36 px-4 pt-5">
        <h2 class="mb-1 font-display text-lg font-semibold text-brand-900">{{ g.category.name }}</h2>
        <ul class="divide-y divide-brand-50">
          <li v-for="p in g.products" :key="p.id" class="flex gap-3 py-4">
            <button class="flex min-w-0 flex-1 gap-3 text-left" :disabled="!p.is_available" @click="selected = p">
              <div class="relative size-24 shrink-0 overflow-hidden rounded-xl bg-brand-100">
                <img v-if="p.image_url" :src="p.image_url" :alt="p.name" loading="lazy" class="h-full w-full object-cover" :class="{ 'grayscale': !p.is_available }">
                <div v-else class="flex h-full w-full items-center justify-center font-display text-3xl text-brand-400">{{ p.name.charAt(0) }}</div>
                <span v-if="badge(p)" class="badge absolute left-1 top-1 !text-[9px]" :class="badge(p)!.class">{{ badge(p)!.text }}</span>
              </div>
              <div class="min-w-0 flex-1 py-0.5">
                <p class="font-semibold leading-tight text-brand-950">{{ p.name }}</p>
                <p class="mt-0.5 line-clamp-2 text-xs leading-snug text-brand-500">{{ p.description }}</p>
                <p class="mt-1.5 text-sm font-bold text-brand-800">{{ fmtIDR(p.price) }}</p>
              </div>
            </button>

            <div class="flex shrink-0 flex-col items-end justify-end">
              <span v-if="!p.is_available" class="badge bg-brand-100 text-brand-500">Habis</span>
              <div v-else-if="cardQty(p) && simpleLine(p)" class="flex items-center gap-2 rounded-xl border border-brand-200 px-1.5">
                <button class="p-2 text-brand-700" :aria-label="`Kurangi ${p.name}`" @click="stepDown(p)"><Icon name="minus" :size="14" /></button>
                <span class="w-4 text-center text-sm font-bold">{{ cardQty(p) }}</span>
                <button class="p-2 text-brand-800" :aria-label="`Tambah ${p.name}`" @click="quickAdd(p)"><Icon name="plus" :size="14" /></button>
              </div>
              <button
                v-else
                class="flex items-center gap-1 rounded-xl border border-brand-300 bg-white px-4 py-2 text-sm font-semibold text-brand-800 shadow-sm active:scale-95"
                @click="quickAdd(p)"
              >
                <template v-if="cardQty(p)">{{ cardQty(p) }} <span class="text-xs">·</span></template>
                Tambah
              </button>
            </div>
          </li>
        </ul>
      </section>

      <div v-if="!grouped.length" class="py-20 text-center">
        <p class="font-display text-lg text-brand-800">Tidak ada menu ditemukan</p>
        <p class="mt-1 text-sm text-brand-500">Coba kata kunci atau kategori lain.</p>
      </div>
    </template>

    <Transition
      enter-active-class="transition duration-200" enter-from-class="translate-y-full"
      leave-active-class="transition duration-150" leave-to-class="translate-y-full"
    >
      <NuxtLink
        v-if="itemCount"
        to="/cart"
        class="fixed inset-x-0 bottom-0 z-40 mx-auto flex max-w-2xl items-center justify-between gap-3 bg-brand-800 px-5 py-4 text-cream shadow-[0_-2px_12px_rgba(61,40,28,0.15)]"
      >
        <span class="flex items-center gap-2 text-sm font-medium">
          <span class="flex size-6 items-center justify-center rounded-full bg-cream/20 text-xs font-bold">{{ itemCount }}</span>
          Lihat Pesanan
        </span>
        <span class="text-sm font-bold">{{ fmtIDR(cartTotal) }}</span>
      </NuxtLink>
    </Transition>

    <ProductSheet :product="selected" @close="selected = null" />
  </div>
</template>
