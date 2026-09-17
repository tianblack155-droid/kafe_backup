<script setup lang="ts">
import type { Product, Variant } from '#shared/types'

const { menu, load } = useMenu()
await useAsyncData('menu-admin', () => load(true))

interface VariantRow {
  id?: string
  group_name: string
  name: string
  price_modifier: number
  is_default: boolean
  is_available: boolean
  sort_order: number
}

interface ProductForm {
  id?: string
  name: string
  category_id: string
  price: number
  description: string
  image_url: string
  is_available: boolean
  is_featured: boolean
  is_best_seller: boolean
  is_new: boolean
  variants: VariantRow[]
  addon_ids: string[]
}

const sheet = ref(false)
const saving = ref(false)
const error = ref('')
const form = ref<ProductForm>({
  name: '',
  category_id: '',
  price: 0,
  description: '',
  image_url: '',
  is_available: true,
  is_featured: false,
  is_best_seller: false,
  is_new: false,
  variants: [],
  addon_ids: []
})

function openNew() {
  form.value = {
    name: '', category_id: menu.value?.categories[0]?.id ?? '', price: 0, description: '',
    image_url: '', is_available: true, is_featured: false, is_best_seller: false, is_new: false,
    variants: [], addon_ids: []
  }
  error.value = ''
  sheet.value = true
}

function openEdit(p: Product) {
  form.value = {
    id: p.id,
    name: p.name,
    category_id: p.category_id,
    price: p.price,
    description: p.description ?? '',
    image_url: p.image_url ?? '',
    is_available: p.is_available,
    is_featured: p.is_featured,
    is_best_seller: p.is_best_seller,
    is_new: p.is_new,
    variants: p.variants.map((v: Variant) => ({
      id: v.id, group_name: v.group_name, name: v.name, price_modifier: v.price_modifier,
      is_default: v.is_default, is_available: v.is_available, sort_order: v.sort_order
    })),
    addon_ids: p.addons.map((a) => a.id)
  }
  error.value = ''
  sheet.value = true
}

async function save() {
  if (!form.value.name.trim() || !form.value.category_id) {
    error.value = 'Nama dan kategori wajib diisi.'
    return
  }
  saving.value = true
  error.value = ''
  try {
    const url: string = form.value.id ? `/api/admin/products/${form.value.id}` : '/api/admin/products'
    await $fetch(url, { method: form.value.id ? 'PATCH' : 'POST', body: form.value })
    sheet.value = false
    await load(true)
  } catch (e: unknown) {
    error.value = (e as { data?: { statusMessage?: string } })?.data?.statusMessage ?? 'Gagal menyimpan produk.'
  } finally {
    saving.value = false
  }
}

async function remove(p: Product) {
  if (!confirm(`Hapus "${p.name}"?`)) return
  const url: string = `/api/admin/crud/products/${p.id}`
  await $fetch(url, { method: 'DELETE' })
  await load(true)
}

async function onFile(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return
  const fd = new FormData()
  fd.append('file', file)
  try {
    const res = await $fetch<{ url: string }>('/api/admin/upload', { method: 'POST', body: fd })
    form.value.image_url = res.url
  } catch {
    error.value = 'Gagal mengunggah gambar (maks 2MB).'
  }
}

function addVariantRow() {
  form.value.variants.push({ group_name: 'Ukuran', name: '', price_modifier: 0, is_default: false, is_available: true, sort_order: form.value.variants.length + 1 })
}

const categoryName = (id: string) => menu.value?.categories.find((c) => c.id === id)?.name ?? '-'

const addonOptions = ref<{ id: string; name: string; price: number }[]>([])
onMounted(async () => {
  addonOptions.value = await $fetch<{ id: string; name: string; price: number }[]>('/api/admin/crud/addons')
})
</script>

<template>
  <div>
    <div class="flex items-center justify-between">
      <h1 class="font-display text-2xl font-bold">Produk</h1>
      <button class="btn btn-primary btn-sm" @click="openNew"><Icon name="plus" :size="16" /> Tambah</button>
    </div>

    <div v-if="!menu?.products.length" class="card mt-5 p-10 text-center text-sm text-brand-500">Belum ada produk.</div>

    <div v-else class="card mt-5 divide-y divide-brand-50">
      <div v-for="p in menu.products" :key="p.id" class="flex items-center gap-3 px-4 py-3">
        <div class="size-11 shrink-0 overflow-hidden rounded-xl bg-brand-100">
          <img v-if="p.image_url" :src="p.image_url" :alt="p.name" class="h-full w-full object-cover">
          <div v-else class="flex h-full w-full items-center justify-center font-display text-brand-400">{{ p.name.charAt(0) }}</div>
        </div>
        <div class="min-w-0 flex-1">
          <p class="truncate font-medium">{{ p.name }}</p>
          <p class="text-xs text-brand-500">{{ categoryName(p.category_id) }} · {{ fmtIDR(p.price) }}
            <span v-if="p.is_best_seller" class="text-gold-600">· Best Seller</span>
            <span v-if="p.is_new" class="text-emerald-600">· Baru</span>
            <span v-if="!p.is_available" class="font-semibold text-red-600">· Habis</span>
          </p>
        </div>
        <button class="btn btn-ghost btn-sm" :aria-label="`Edit ${p.name}`" @click="openEdit(p)"><Icon name="pencil" :size="15" /></button>
        <button class="btn btn-ghost btn-sm !text-red-600" :aria-label="`Hapus ${p.name}`" @click="remove(p)"><Icon name="trash" :size="15" /></button>
      </div>
    </div>

    <AppSheet :open="sheet" :title="form.id ? 'Edit Produk' : 'Tambah Produk'" @close="sheet = false">
      <div v-if="error" class="mb-4 rounded-xl bg-red-50 px-4 py-2.5 text-sm text-red-700" role="alert">{{ error }}</div>

      <div class="space-y-4">
        <div class="flex items-start gap-3">
          <div class="size-20 shrink-0 overflow-hidden rounded-xl bg-brand-100">
            <img v-if="form.image_url" :src="form.image_url" alt="Preview produk" class="h-full w-full object-cover">
            <div v-else class="flex h-full w-full items-center justify-center text-brand-400"><Icon name="image" :size="24" /></div>
          </div>
          <div class="flex-1">
            <label class="label" for="p-image">Gambar (maks 2MB)</label>
            <input id="p-image" type="file" accept="image/*" class="text-sm" @change="onFile">
          </div>
        </div>

        <div>
          <label class="label" for="p-name">Nama</label>
          <input id="p-name" v-model="form.name" class="input" maxlength="100">
        </div>
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="label" for="p-cat">Kategori</label>
            <select id="p-cat" v-model="form.category_id" class="input">
              <option v-for="c in menu?.categories" :key="c.id" :value="c.id">{{ c.name }}</option>
            </select>
          </div>
          <div>
            <label class="label" for="p-price">Harga (Rp)</label>
            <input id="p-price" v-model.number="form.price" type="number" min="0" step="500" class="input">
          </div>
        </div>
        <div>
          <label class="label" for="p-desc">Deskripsi</label>
          <textarea id="p-desc" v-model="form.description" rows="2" class="input h-auto py-2.5" maxlength="300" />
        </div>

        <div class="flex flex-wrap gap-x-5 gap-y-2 text-sm">
          <label class="flex items-center gap-2"><input v-model="form.is_available" type="checkbox" class="size-4 accent-brand-800"> Tersedia</label>
          <label class="flex items-center gap-2"><input v-model="form.is_best_seller" type="checkbox" class="size-4 accent-brand-800"> Best Seller</label>
          <label class="flex items-center gap-2"><input v-model="form.is_new" type="checkbox" class="size-4 accent-brand-800"> Baru</label>
          <label class="flex items-center gap-2"><input v-model="form.is_featured" type="checkbox" class="size-4 accent-brand-800"> Rekomendasi</label>
        </div>

        <div>
          <div class="mb-1.5 flex items-center justify-between">
            <p class="label !mb-0">Varian</p>
            <button class="btn btn-ghost btn-sm" type="button" @click="addVariantRow"><Icon name="plus" :size="14" /> Tambah</button>
          </div>
          <div v-for="(v, i) in form.variants" :key="i" class="mb-2 flex flex-wrap items-center gap-2">
            <input v-model="v.group_name" class="input !h-9 w-24 text-xs" placeholder="Grup" aria-label="Grup varian">
            <input v-model="v.name" class="input !h-9 min-w-24 flex-1 text-sm" placeholder="Nama" :aria-label="`Nama varian ${i + 1}`">
            <input v-model.number="v.price_modifier" type="number" min="0" step="500" class="input !h-9 w-24 text-sm" placeholder="+Rp" aria-label="Tambahan harga">
            <label class="flex items-center gap-1 text-xs" :for="`def-${i}`">Default<input :id="`def-${i}`" v-model="v.is_default" type="checkbox" class="size-4 accent-brand-800"></label>
            <button type="button" class="btn btn-ghost btn-sm !text-red-600" :aria-label="`Hapus varian ${i + 1}`" @click="form.variants.splice(i, 1)"><Icon name="trash" :size="14" /></button>
          </div>
        </div>

        <div>
          <p class="label">Add-on Tersedia</p>
          <div class="flex flex-wrap gap-2">
            <label
              v-for="a in addonOptions"
              :key="a.id"
              class="flex cursor-pointer items-center gap-2 rounded-xl border px-3 py-2 text-sm"
              :class="form.addon_ids.includes(a.id) ? 'border-brand-800 bg-brand-50' : 'border-brand-200'"
            >
              <input
                type="checkbox"
                class="size-4 accent-brand-800"
                :checked="form.addon_ids.includes(a.id)"
                @change="form.addon_ids = ($event.target as HTMLInputElement).checked ? [...form.addon_ids, a.id] : form.addon_ids.filter((id) => id !== a.id)"
              >
              {{ a.name }} +{{ fmtIDR(a.price) }}
            </label>
          </div>
        </div>

        <button class="btn btn-primary w-full" :disabled="saving" @click="save">
          {{ saving ? 'Menyimpan...' : 'Simpan Produk' }}
        </button>
      </div>
    </AppSheet>
  </div>
</template>
