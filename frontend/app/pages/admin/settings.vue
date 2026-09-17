<script setup lang="ts">
import type { Settings } from '#shared/types'

const form = ref<Settings | null>(null)
const saved = ref(false)

onMounted(async () => {
  const rows = await $fetch<Settings[]>('/api/admin/crud/settings')
  form.value = rows[0] ?? null
})

async function save() {
  if (!form.value) return
  await $fetch('/api/admin/crud/settings/1', {
    method: 'PATCH',
    body: {
      brand_name: form.value.brand_name,
      tagline: form.value.tagline,
      tax_pct: Number(form.value.tax_pct) || 0,
      service_pct: Number(form.value.service_pct) || 0,
      require_customer_name: form.value.require_customer_name
    }
  })
  saved.value = true
  setTimeout(() => (saved.value = false), 2000)
}
</script>

<template>
  <div class="max-w-lg">
    <h1 class="font-display text-2xl font-bold">Pengaturan</h1>

    <div v-if="form" class="card mt-5 space-y-4 p-5">
      <div>
        <label class="label" for="s-brand">Nama Cafe</label>
        <input id="s-brand" v-model="form.brand_name" class="input" maxlength="50">
      </div>
      <div>
        <label class="label" for="s-tagline">Tagline</label>
        <input id="s-tagline" v-model="form.tagline" class="input" maxlength="100">
      </div>
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="label" for="s-service">Service Charge (%)</label>
          <input id="s-service" v-model.number="form.service_pct" type="number" min="0" max="100" step="0.5" class="input">
        </div>
        <div>
          <label class="label" for="s-tax">Pajak (%)</label>
          <input id="s-tax" v-model.number="form.tax_pct" type="number" min="0" max="100" step="0.5" class="input">
        </div>
      </div>
      <label class="flex items-center gap-2 text-sm">
        <input v-model="form.require_customer_name" type="checkbox" class="size-4 accent-brand-800">
        Wajib isi nama pelanggan saat checkout
      </label>
      <button class="btn btn-primary w-full" @click="save">{{ saved ? 'Tersimpan ✓' : 'Simpan' }}</button>
    </div>
  </div>
</template>
