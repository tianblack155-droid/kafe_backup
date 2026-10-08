<script setup lang="ts">
import { restaurantHours, restaurantStatus } from '#shared/restaurant-hours'

const expanded = ref(false)
const scheduleId = useId()
const now = ref<Date | null>(null)
const status = computed(() => now.value ? restaurantStatus(now.value) : null)
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  now.value = new Date()
  timer = setInterval(() => { now.value = new Date() }, 30_000)
})
onUnmounted(() => clearInterval(timer))
</script>

<template>
  <div class="customer-hours">
    <button type="button" class="customer-hours-toggle" :aria-expanded="expanded" :aria-controls="scheduleId" @click="expanded = !expanded">
      <Icon name="clock" :size="20" />
      <span v-if="status" class="customer-hours-summary">
        Sekarang <strong :class="status.isOpen ? 'customer-hours-open' : 'customer-hours-closed'">{{ status.isOpen ? 'Buka' : 'Tutup' }}</strong>, {{ status.detail }}
      </span>
      <span v-else class="customer-hours-summary">Jam operasional</span>
      <Icon name="chevron-down" :size="16" class="customer-hours-chevron" />
    </button>
    <div :id="scheduleId" class="customer-hours-collapse" :class="{ expanded }" :aria-hidden="!expanded" :inert="!expanded">
      <div class="customer-hours-content">
        <dl class="customer-hours-list" aria-label="Jam operasional dalam WIB">
          <div v-for="(hours, index) in restaurantHours" :key="hours.day" :class="{ 'customer-hours-today': status?.dayIndex === index }">
            <dt>{{ hours.day }}<span v-if="status?.dayIndex === index" class="customer-sr-only"> (hari ini)</span></dt>
            <dd>{{ hours.open }}–{{ hours.close }}</dd>
          </div>
        </dl>
      </div>
    </div>
  </div>
</template>
