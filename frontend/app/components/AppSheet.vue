<script setup lang="ts">
const props = defineProps<{ open: boolean; title?: string }>()
const emit = defineEmits<{ close: [] }>()

function onEsc(e: KeyboardEvent) {
  if (e.key === 'Escape') emit('close')
}

watch(() => props.open, (v) => {
  if (!import.meta.client) return
  document.body.style.overflow = v ? 'hidden' : ''
  window.removeEventListener('keydown', onEsc)
  if (v) window.addEventListener('keydown', onEsc)
})

onUnmounted(() => {
  if (!import.meta.client) return
  document.body.style.overflow = ''
  window.removeEventListener('keydown', onEsc)
})
</script>

<template>
  <Teleport to="body">
    <div v-if="props.open" class="fixed inset-0 z-50">
      <div class="absolute inset-0 bg-brand-950/40" @click="emit('close')" />
      <div
        role="dialog"
        aria-modal="true"
        :aria-label="props.title"
        class="absolute inset-x-0 bottom-0 max-h-[92dvh] overflow-y-auto rounded-t-3xl bg-white shadow-xl sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-1/2 sm:max-h-[85dvh] sm:w-full sm:max-w-lg sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-2xl"
      >
        <div v-if="props.title" class="sticky top-0 z-10 flex items-center justify-between border-b border-brand-100 bg-white px-5 py-4">
          <h2 class="font-display text-lg font-semibold text-brand-950">{{ props.title }}</h2>
          <button class="btn btn-ghost btn-sm" aria-label="Tutup" @click="emit('close')">
            <Icon name="x" :size="18" />
          </button>
        </div>
        <div class="px-5 py-4">
          <slot />
        </div>
        <slot name="footer" />
      </div>
    </div>
  </Teleport>
</template>
