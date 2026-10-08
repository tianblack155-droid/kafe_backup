<script setup lang="ts">
const props = withDefaults(defineProps<{ src?: string | null; alt: string; logo?: boolean; eager?: boolean }>(), { logo: false, eager: false })
const failed = ref(false)
watch(() => props.src, () => { failed.value = false })
</script>

<template>
  <div class="customer-image" :class="{ 'customer-logo': logo }">
    <img v-if="src && !failed" :src="src" :alt="alt" :loading="eager ? 'eager' : 'lazy'" @error="failed = true">
    <div v-else class="customer-placeholder" role="img" :aria-label="logo ? alt : `Foto ${alt} belum tersedia`">
      <template v-if="logo"><span class="customer-monogram">TKM<span>TERAS KAYU MANIS</span></span></template>
      <template v-else><Icon name="image" :size="30" /><span>Foto belum tersedia</span></template>
    </div>
  </div>
</template>
