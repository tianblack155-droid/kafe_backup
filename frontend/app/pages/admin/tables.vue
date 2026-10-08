<script setup lang="ts">
import QRCode from 'qrcode'

interface TableRow { id: string; number: number; qr_token: string; is_active: boolean }

const rows = ref<TableRow[]>([])
const qrDataUrl = ref('')
const qrTable = ref<TableRow | null>(null)
const addOpen = ref(false)
const newNumber = ref<number | null>(null)

async function load() {
  rows.value = (await $fetch<TableRow[]>('/api/admin/crud/tables')).sort((a, b) => a.number - b.number)
}
onMounted(load)

async function save() {
  if (!newNumber.value || newNumber.value < 1) return
  try {
    await $fetch('/api/admin/crud/tables', { method: 'POST', body: { number: newNumber.value } })
  } catch {
    alert('Nomor meja sudah dipakai.')
  }
  addOpen.value = false
  newNumber.value = null
  await load()
}

async function toggle(t: TableRow) {
  await $fetch(`/api/admin/crud/tables/${t.id}`, { method: 'PATCH', body: { is_active: !t.is_active } })
  await load()
}

async function remove(t: TableRow) {
  if (!confirm(`Hapus Meja ${t.number}?`)) return
  try {
    await $fetch(`/api/admin/crud/tables/${t.id}`, { method: 'DELETE' })
  } catch {
    alert('Meja memiliki riwayat pesanan dan tidak dapat dihapus. Nonaktifkan saja.')
  }
  await load()
}

async function showQr(t: TableRow) {
  qrTable.value = t
  const url = `${location.origin}/menu?t=${t.qr_token}`
  qrDataUrl.value = await QRCode.toDataURL(url, { width: 280, margin: 1 })
}

async function rotateToken() {
  if (!qrTable.value || !confirm('Buat ulang token QR? QR lama tidak akan berfungsi lagi.')) return
  const res = await $fetch<{ qr_token: string }>(`/api/admin/tables/${qrTable.value.id}/token`, { method: 'POST' })
  const updated = rows.value.find((r) => r.id === qrTable.value!.id)
  if (updated) updated.qr_token = res.qr_token
  await showQr({ ...qrTable.value, qr_token: res.qr_token })
  alert('Token baru dibuat. Unduh ulang QR dan tempel di meja.')
}
</script>

<template>
  <div>
    <div class="flex items-center justify-between">
      <h1 class="font-display text-2xl font-bold">Meja & QR</h1>
      <button class="btn btn-primary btn-sm" @click="addOpen = true"><Icon name="plus" :size="16" /> Tambah Meja</button>
    </div>

    <div class="card mt-5 divide-y divide-brand-50">
      <div v-for="t in rows" :key="t.id" class="flex items-center gap-3 px-4 py-3">
        <p class="font-display text-lg font-bold">Meja {{ t.number }}</p>
        <span class="badge" :class="t.is_active ? 'bg-emerald-100 text-emerald-700' : 'bg-brand-100 text-brand-500'">
          {{ t.is_active ? 'Aktif' : 'Nonaktif' }}
        </span>
        <div class="ml-auto flex items-center gap-1">
          <button class="btn btn-outline btn-sm" @click="showQr(t)"><Icon name="qr" :size="15" /> QR</button>
          <button class="btn btn-ghost btn-sm" :aria-label="`Aktif/nonaktif meja ${t.number}`" @click="toggle(t)">
            {{ t.is_active ? 'Nonaktifkan' : 'Aktifkan' }}
          </button>
          <button class="btn btn-ghost btn-sm !text-red-600" :aria-label="`Hapus meja ${t.number}`" @click="remove(t)"><Icon name="trash" :size="15" /></button>
        </div>
      </div>
    </div>

    <AppSheet :open="qrTable !== null" :title="`QR Meja ${qrTable?.number}`" @close="qrTable = null">
      <div class="text-center">
        <img v-if="qrDataUrl" :src="qrDataUrl" :alt="`QR code meja ${qrTable?.number}`" class="mx-auto rounded-xl border border-brand-100">
        <p class="mt-3 text-sm text-brand-500">Scan QR ini untuk memesan dari Meja {{ qrTable?.number }}.</p>
        <div class="mt-4 flex justify-center gap-2">
          <a :href="qrDataUrl" :download="`meja-${qrTable?.number}.png`" class="btn btn-primary btn-sm"><Icon name="download" :size="15" /> Unduh</a>
          <button class="btn btn-outline btn-sm" @click="rotateToken">Buat Ulang Token</button>
        </div>
      </div>
    </AppSheet>

    <AppSheet :open="addOpen" title="Tambah Meja" @close="addOpen = false">
      <div class="space-y-4">
        <div>
          <label class="label" for="table-num">Nomor Meja</label>
          <input id="table-num" v-model.number="newNumber" type="number" min="1" class="input" @keyup.enter="save">
        </div>
        <button class="btn btn-primary w-full" @click="save">Simpan</button>
      </div>
    </AppSheet>
  </div>
</template>
