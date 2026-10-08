<script setup lang="ts">
const props = defineProps<{ open: boolean; title: string }>()
const emit = defineEmits<{ close: [] }>()
const dialog = ref<HTMLDialogElement | null>(null)
const titleId = useId()
let previousFocus: HTMLElement | null = null
let previousOverflow = ''
let locked = false
const state = ref<'open' | 'closing'>('open')
let animation: Animation | undefined
let revision = 0
function unlock() {
  if (!locked) return
  document.body.style.overflow = previousOverflow
  locked = false
  previousFocus?.focus()
}
watch(() => props.open, async open => {
  if (!import.meta.client) return
  const currentRevision = ++revision
  await nextTick()
  const element = dialog.value
  if (!element || currentRevision !== revision || (!open && !element.open)) return
  const wasOpen = element.open
  // Preserve the current position when an opening/closing animation is interrupted.
  const from = wasOpen ? { transform: getComputedStyle(element).transform, opacity: getComputedStyle(element).opacity }
    : { transform: 'translateY(100%)', opacity: '0' }
  animation?.cancel()
  state.value = open ? 'open' : 'closing'
  if (open && !wasOpen) {
    previousFocus = document.activeElement as HTMLElement
    previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    locked = true
    element.showModal()
  }
  if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    animation = element.animate([from, {
      transform: open ? 'translateY(0)' : 'translateY(100%)', opacity: open ? '1' : '0',
    }], { duration: 320, easing: 'cubic-bezier(0.22, 1, 0.36, 1)', fill: 'forwards' })
    try { await animation.finished } catch { return }
  }
  if (currentRevision !== revision) return
  if (!open) { element.close(); unlock() }
  animation?.cancel()
  animation = undefined
}, { immediate: true })
function onBackdrop(event: MouseEvent) {
  if (event.target !== dialog.value) return
  const bounds = dialog.value!.getBoundingClientRect()
  if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) emit('close')
}
onBeforeUnmount(() => { revision++; animation?.cancel(); dialog.value?.close(); unlock() })
</script>

<template>
  <dialog ref="dialog" class="customer-modal" :data-state="state" :aria-labelledby="titleId" @cancel.prevent="emit('close')" @click="onBackdrop">
    <div class="customer-modal-header"><h2 :id="titleId">{{ title }}</h2><button class="customer-icon" aria-label="Tutup" @click="emit('close')"><Icon name="x" /></button></div>
    <slot />
  </dialog>
</template>
