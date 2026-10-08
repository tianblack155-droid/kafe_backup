<script setup lang="ts">
interface AddonRow { id: string; name: string; price: number; is_available: boolean }

const rows = ref<AddonRow[]>([])
const sheet = ref(false)
const form = ref<{ id?: string; name: string; price: number }>({ name: '', price: 0 })

async function load() {
  rows.value = await $fetch<AddonRow[]>('/api/admin/crud/addons')
}
onMounted(load)

async function save() {
  if (!form.value.name.trim() || form.value.price < 0) return
  if (form.value.id) await $fetch(`/api/admin/crud/addons/${form.value.id}`, { method: 'PATCH', body: { name: form.value.name, price: form.value.price } })
  else await $fetch('/api/admin/crud/addons', { method: 'POST', body: { name: form.value.name, price: form.value.price } })
  sheet.value = false
  await load()
}

async function toggle(a: AddonRow) {
  await $fetch(`/api/admin/crud/addons/${a.id}`, { method: 'PATCH', body: { is_available: !a.is_available } })
  await load()
}

async function remove(a: AddonRow) {
  if (!confirm(`Hapus add-on "${a.name}"?`)) return
  await $fetch(`/api/admin/crud/addons/${a.id}`, { method: 'DELETE' })
  await load()
}
</script>

<template>
  <div>
    <div class="flex items-center justify-between">
      <h1 class="font-display text-2xl font-bold">Add-on</h1>
      <button class="btn btn-primary btn-sm" @click="form = { name: '', price: 0 }; sheet = true"><Icon name="plus" :size="16" /> Tambah</button>
    </div>

    <div class="card mt-5 divide-y divide-brand-50">
      <div v-for="a in rows" :key="a.id" class="flex items-center gap-3 px-4 py-3">
        <div class="min-w-0 flex-1">
          <p class="font-medium">{{ a.name }}</p>
          <p class="text-xs text-brand-500">+{{ fmtIDR(a.price) }}</p>
        </div>
        <button
          class="badge cursor-pointer"
          :class="a.is_available ? 'bg-emerald-100 text-emerald-700' : 'bg-brand-100 text-brand-500'"
          @click="toggle(a)"
        >
          {{ a.is_available ? 'Aktif' : 'Nonaktif' }}
        </button>
        <button class="btn btn-ghost btn-sm" :aria-label="`Edit ${a.name}`" @click="form = { id: a.id, name: a.name, price: a.price }; sheet = true"><Icon name="pencil" :size="15" /></button>
        <button class="btn btn-ghost btn-sm !text-red-600" :aria-label="`Hapus ${a.name}`" @click="remove(a)"><Icon name="trash" :size="15" /></button>
      </div>
    </div>

    <AppSheet :open="sheet" :title="form.id ? 'Edit Add-on' : 'Tambah Add-on'" @close="sheet = false">
      <div class="space-y-4">
        <div>
          <label class="label" for="addon-name">Nama</label>
          <input id="addon-name" v-model="form.name" class="input" maxlength="50">
        </div>
        <div>
          <label class="label" for="addon-price">Harga (Rp)</label>
          <input id="addon-price" v-model.number="form.price" type="number" min="0" step="500" class="input">
        </div>
        <button class="btn btn-primary w-full" @click="save">Simpan</button>
      </div>
    </AppSheet>
  </div>
</template>
