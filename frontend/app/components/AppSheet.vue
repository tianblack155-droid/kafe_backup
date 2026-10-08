<script setup lang="ts">
const props = defineProps<{ open: boolean; title?: string }>()
const emit = defineEmits<{ close: [] }>()
let previousOverflow = ''
let locked = false

function unlock() {
  if (!locked || props.open) return
  document.body.style.overflow = previousOverflow
  locked = false
}

function onEsc(e: KeyboardEvent) {
  if (e.key === 'Escape') emit('close')
}

watch(() => props.open, (v) => {
  if (!import.meta.client) return
  if (v && !locked) {
    previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    locked = true
  }
  window.removeEventListener('keydown', onEsc)
  if (v) window.addEventListener('keydown', onEsc)
}, { immediate: true })

onUnmounted(() => {
  if (!import.meta.client) return
  if (locked) document.body.style.overflow = previousOverflow
  window.removeEventListener('keydown', onEsc)
})
</script>

<template>
  <Teleport to="body">
    <Transition name="app-sheet" :duration="320" @after-leave="unlock">
    <div v-if="props.open" class="fixed inset-0 z-50">
      <div class="app-sheet-backdrop absolute inset-0 bg-brand-950/40" @click="emit('close')" />
      <div
        role="dialog"
        aria-modal="true"
        :aria-label="props.title"
        class="app-sheet-panel absolute inset-x-0 bottom-0 max-h-[92dvh] overflow-y-auto rounded-t-3xl bg-white shadow-xl sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-1/2 sm:max-h-[85dvh] sm:w-full sm:max-w-lg sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-2xl"
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
    </Transition>
  </Teleport>
</template>
