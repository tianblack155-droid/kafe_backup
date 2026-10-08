<script setup lang="ts">
interface Stats {
  today_total: number
  today_revenue: number
  active_total: number
  counts: Record<string, number>
  popular: { name: string; qty: number }[]
}

const stats = ref<Stats | null>(null)

onMounted(async () => {
  stats.value = await $fetch<Stats>('/api/admin/stats')
})

const cards = computed(() => stats.value ? [
  { label: 'Pesanan Hari Ini', value: String(stats.value.today_total) },
  { label: 'Pendapatan (Lunas)', value: fmtIDR(stats.value.today_revenue) },
  { label: 'Pesanan Aktif', value: String(stats.value.active_total) },
  { label: 'Selesai', value: String(stats.value.counts.completed ?? 0) }
] : [])
</script>

<template>
  <div>
    <h1 class="font-display text-2xl font-bold">Dashboard</h1>
    <p class="text-sm text-brand-500">Ringkasan operasional hari ini.</p>

    <div class="mt-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
      <div v-for="c in cards" :key="c.label" class="card p-4">
        <p class="text-xs text-brand-500">{{ c.label }}</p>
        <p class="mt-1 font-display text-xl font-bold text-brand-950">{{ c.value }}</p>
      </div>
    </div>

    <div class="mt-6 grid gap-4 lg:grid-cols-2">
      <div class="card p-5">
        <h2 class="mb-3 font-semibold">Status Pesanan</h2>
        <div v-if="stats" class="space-y-2 text-sm">
          <div v-for="[label, key] in [['Menunggu', 'pending'], ['Disiapkan', 'preparing'], ['Siap', 'ready'], ['Selesai', 'completed'], ['Batal', 'cancelled']]" :key="key" class="flex justify-between">
            <span class="text-brand-500">{{ label }}</span><span class="font-semibold">{{ stats.counts[key] ?? 0 }}</span>
          </div>
        </div>
      </div>

      <div class="card p-5">
        <h2 class="mb-3 font-semibold">Menu Terpopuler Hari Ini</h2>
        <div v-if="stats?.popular.length" class="space-y-2 text-sm">
          <div v-for="(p, i) in stats.popular" :key="p.name" class="flex items-center gap-3">
            <span class="flex size-6 items-center justify-center rounded-full bg-brand-100 text-xs font-bold text-brand-700">{{ i + 1 }}</span>
            <span class="flex-1 truncate">{{ p.name }}</span>
            <span class="font-semibold">{{ p.qty }}x</span>
          </div>
        </div>
        <p v-else class="text-sm text-brand-500">Belum ada pesanan hari ini.</p>
      </div>
    </div>
  </div>
</template>
