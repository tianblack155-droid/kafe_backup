<script setup lang="ts">
import type { Product } from '#shared/types'

const props = defineProps<{ product: Product | null }>()
const emit = defineEmits<{ close: []; added: [] }>()

const { add } = useCart()
const selections = ref<Record<string, string>>({})
const addonIds = ref<string[]>([])
const qty = ref(1)
const notes = ref('')

const groups = computed(() => {
  if (!props.product) return []
  const map = new Map<string, typeof props.product.variants>()
  for (const v of props.product.variants) {
    if (!map.has(v.group_name)) map.set(v.group_name, [])
    map.get(v.group_name)!.push(v)
  }
  return [...map.entries()]
})

watch(() => props.product, (p) => {
  if (!p) return
  const init: Record<string, string> = {}
  for (const [group, variants] of groups.value) {
    const def = variants.find((v) => v.is_default && v.is_available) ?? variants.find((v) => v.is_available)
    if (def) init[group] = def.id
  }
  selections.value = init
  addonIds.value = []
  qty.value = 1
  notes.value = ''
}, { immediate: true })

const unitPrice = computed(() => {
  if (!props.product) return 0
  let price = props.product.price
  for (const v of props.product.variants) {
    if (Object.values(selections.value).includes(v.id)) price += v.price_modifier
  }
  for (const a of props.product.addons) {
    if (addonIds.value.includes(a.id)) price += a.price
  }
  return price
})

function submit() {
  if (!props.product) return
  add({
    productId: props.product.id,
    variantIds: Object.values(selections.value),
    addonIds: [...addonIds.value],
    qty: qty.value,
    notes: notes.value
  })
  emit('added')
  emit('close')
}
</script>

<template>
  <AppSheet :open="!!product" :title="product?.name" @close="emit('close')">
    <template v-if="product">
      <div class="-mx-5 -mt-4 mb-4 h-44 overflow-hidden bg-brand-100">
        <img v-if="product.image_url" :src="product.image_url" :alt="product.name" class="h-full w-full object-cover">
        <div v-else class="flex h-full w-full items-center justify-center bg-gradient-to-br from-brand-100 to-brand-200 font-display text-5xl text-brand-500">
          {{ product.name.charAt(0) }}
        </div>
      </div>

      <p v-if="product.description" class="mb-3 text-sm text-brand-600">{{ product.description }}</p>

      <div v-for="[group, variants] in groups" :key="group" class="mb-4">
        <p class="label">{{ group }}</p>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="v in variants"
            :key="v.id"
            type="button"
            :disabled="!v.is_available"
            class="rounded-xl border px-3.5 py-2 text-sm transition disabled:opacity-40"
            :class="selections[group] === v.id ? 'border-brand-800 bg-brand-800 text-cream' : 'border-brand-200 bg-white text-brand-800'"
            @click="selections[group] = v.id"
          >
            {{ v.name }}<span v-if="v.price_modifier > 0" class="opacity-80"> +{{ fmtIDR(v.price_modifier) }}</span>
          </button>
        </div>
      </div>

      <div v-if="product.addons.length" class="mb-4">
        <p class="label">Tambahan</p>
        <label
          v-for="a in product.addons"
          :key="a.id"
          class="mb-1.5 flex items-center justify-between rounded-xl border border-brand-100 px-3.5 py-2.5 text-sm"
          :class="a.is_available ? 'cursor-pointer' : 'cursor-not-allowed opacity-50'"
        >
          <span class="flex items-center gap-2.5">
            <input v-model="addonIds" type="checkbox" :value="a.id" :disabled="!a.is_available" class="size-4 accent-brand-800">
            <span>{{ a.name }}</span><span v-if="!a.is_available" class="text-xs text-red-500">(habis)</span>
          </span>
          <span class="text-brand-500">+{{ fmtIDR(a.price) }}</span>
        </label>
      </div>

      <div class="mb-4">
        <p class="label">Catatan khusus</p>
        <textarea
          v-model="notes"
          rows="2"
          placeholder="Contoh: less spicy, please"
          class="input h-auto py-2.5"
          maxlength="200"
        />
      </div>

      <div class="flex items-center gap-3">
        <div class="flex items-center gap-3 rounded-xl border border-brand-200 px-3">
          <button type="button" aria-label="Kurangi" class="py-3 text-brand-600" @click="qty = Math.max(1, qty - 1)"><Icon name="minus" :size="16" /></button>
          <span class="w-6 text-center font-semibold">{{ qty }}</span>
          <button type="button" aria-label="Tambah" class="py-3 text-brand-800" @click="qty = Math.min(50, qty + 1)"><Icon name="plus" :size="16" /></button>
        </div>
        <button type="button" class="btn btn-primary flex-1" @click="submit">
          Tambah · {{ fmtIDR(unitPrice * qty) }}
        </button>
      </div>
    </template>
  </AppSheet>
</template>
