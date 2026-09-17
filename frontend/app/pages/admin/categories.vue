<script setup lang="ts">
import type { Category } from '#shared/types'

const rows = ref<Category[]>([])
const sheet = ref(false)
const form = ref<{ id?: string; name: string }>({ name: '' })

async function load() {
  rows.value = await $fetch<Category[]>('/api/admin/crud/categories')
}
onMounted(load)

async function save() {
  if (!form.value.name.trim()) return
  const slug = form.value.name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '')
  if (form.value.id) await $fetch(`/api/admin/crud/categories/${form.value.id}`, { method: 'PATCH', body: { name: form.value.name } })
  else await $fetch('/api/admin/crud/categories', { method: 'POST', body: { name: form.value.name, slug: slug + '-' + Math.random().toString(36).slice(2, 6), sort_order: rows.value.length + 1 } })
  sheet.value = false
  await load()
}

async function toggleActive(c: Category) {
  await $fetch(`/api/admin/crud/categories/${c.id}`, { method: 'PATCH', body: { is_active: !c.is_active } })
  await load()
}

async function move(c: Category, dir: -1 | 1) {
  const sorted = [...rows.value].sort((a, b) => a.sort_order - b.sort_order)
  const i = sorted.findIndex((r) => r.id === c.id)
  const j = i + dir
  const a = sorted[i]
  const b = sorted[j]
  if (j < 0 || j >= sorted.length || !a || !b) return
  await Promise.all([
    $fetch(`/api/admin/crud/categories/${a.id}`, { method: 'PATCH', body: { sort_order: b.sort_order } }),
    $fetch(`/api/admin/crud/categories/${b.id}`, { method: 'PATCH', body: { sort_order: a.sort_order } })
  ])
  await load()
}

async function remove(c: Category) {
  if (!confirm(`Hapus kategori "${c.name}"?`)) return
  try {
    await $fetch(`/api/admin/crud/categories/${c.id}`, { method: 'DELETE' })
  } catch (e: unknown) {
    alert((e as { data?: { statusMessage?: string } })?.data?.statusMessage ?? 'Tidak dapat dihapus, masih dipakai produk.')
  }
  await load()
}
</script>

<template>
  <div>
    <div class="flex items-center justify-between">
      <h1 class="font-display text-2xl font-bold">Kategori</h1>
      <button class="btn btn-primary btn-sm" @click="form = { name: '' }; sheet = true"><Icon name="plus" :size="16" /> Tambah</button>
    </div>

    <div class="card mt-5 divide-y divide-brand-50">
      <div v-for="(c, i) in [...rows].sort((a, b) => a.sort_order - b.sort_order)" :key="c.id" class="flex items-center gap-2 px-4 py-3">
        <div class="flex flex-col">
          <button class="btn btn-ghost btn-sm !h-6 !px-1.5" :aria-label="`Naikkan ${c.name}`" :disabled="i === 0" @click="move(c, -1)"><Icon name="chevron-up" :size="14" /></button>
          <button class="btn btn-ghost btn-sm !h-6 !px-1.5" :aria-label="`Turunkan ${c.name}`" :disabled="i === rows.length - 1" @click="move(c, 1)"><Icon name="chevron-down" :size="14" /></button>
        </div>
        <div class="min-w-0 flex-1">
          <p class="font-medium">{{ c.name }}</p>
          <p class="text-xs text-brand-400">/{{ c.slug }}</p>
        </div>
        <button
          class="badge cursor-pointer"
          :class="c.is_active ? 'bg-emerald-100 text-emerald-700' : 'bg-brand-100 text-brand-500'"
          @click="toggleActive(c)"
        >
          {{ c.is_active ? 'Aktif' : 'Nonaktif' }}
        </button>
        <button class="btn btn-ghost btn-sm" :aria-label="`Edit ${c.name}`" @click="form = { id: c.id, name: c.name }; sheet = true"><Icon name="pencil" :size="15" /></button>
        <button class="btn btn-ghost btn-sm !text-red-600" :aria-label="`Hapus ${c.name}`" @click="remove(c)"><Icon name="trash" :size="15" /></button>
      </div>
    </div>

    <AppSheet :open="sheet" :title="form.id ? 'Edit Kategori' : 'Tambah Kategori'" @close="sheet = false">
      <div>
        <label class="label" for="cat-name">Nama</label>
        <input id="cat-name" v-model="form.name" class="input" maxlength="50" @keyup.enter="save">
        <button class="btn btn-primary mt-4 w-full" @click="save">Simpan</button>
      </div>
    </AppSheet>
  </div>
</template>
