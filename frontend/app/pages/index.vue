<script setup lang="ts">
definePageMeta({ layout: 'customer' })
const { menu, load } = useMenu()
const tutorialOpen = ref(false)
const error = ref('')
const brand = computed(() => menu.value?.settings.brand_name || 'TerasKayuManis')
useHead(() => ({ title: brand.value }))
async function refresh() {
  error.value = ''
  try { await load() } catch { error.value = 'Informasi restoran belum dapat dimuat.' }
}
onMounted(refresh)
</script>

<template>
  <main class="customer-shell customer-landing">
    <div class="customer-cover customer-cover-photo">
      <img src="/images/restaurant-terrace.webp" alt="Teras restoran Teras Kayu Manis dengan meja kayu dan pepohonan" fetchpriority="high" width="408" height="543">
    </div>
    <section class="customer-welcome">
      <CustomerImage :src="menu?.settings.logo_url || '/images/restaurant-logo-round.webp'" :alt="brand" logo eager />
      <h1>{{ brand }}</h1>
      <p v-if="menu?.settings.tagline" class="customer-muted">{{ menu.settings.tagline }}</p>
      <div class="customer-restaurant-details">
        <div class="customer-address-row">
          <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.5"/></svg>
          <p>Jl. Cilengkrang II No.79, Palasari, Kec. Cibiru, Kota Bandung, Jawa Barat 40615</p>
          <a href="https://maps.app.goo.gl/64bfw1KhogyUspXN6" target="_blank" rel="noopener noreferrer">Buka peta</a>
        </div>
        <RestaurantHours />
        <a class="customer-contact-row" href="https://wa.me/6282246851927" target="_blank" rel="noopener noreferrer">
          <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M21 11.5a9 9 0 0 1-13.5 7.8L3 21l1.7-4.5A9 9 0 1 1 21 11.5Z"/><path d="M8 7c0 5 4 9 9 9l1-3-3-1-1 1-3-3 1-1-1-3Z"/></svg>
          <span>Hubungi Restoran <small>WhatsApp · 082246851927</small></span><span aria-hidden="true">↗</span>
        </a>
        <a class="customer-contact-row" href="https://www.instagram.com/teraskayumanis.id/" target="_blank" rel="noopener noreferrer">
          <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.5" cy="6.5" r=".8"/></svg>
          <span>Instagram <small>@teraskayumanis.id</small></span><span aria-hidden="true">↗</span>
        </a>
      </div>

      <div v-if="error" role="alert"><p>{{ error }}</p><button class="customer-text-button" @click="refresh">Coba lagi</button></div>
    </section>
    <div class="customer-entry-actions">
      <button class="customer-tutorial-entry" aria-label="Cara Memesan" @click="tutorialOpen = true"><span class="customer-help-symbol" aria-hidden="true">?</span><span>Cara order</span><span class="customer-entry-accent">Lihat Tutorial</span></button>
      <NuxtLink to="/menu" class="customer-dine-entry"><Icon name="bag" :size="24" /><span>Makan di Tempat</span><span class="customer-entry-chevron" aria-hidden="true">›</span></NuxtLink>
    </div>
    <footer class="customer-powered-by"><span>Powered by</span><img src="/images/allevi-dev.webp" alt="allevi.dev" width="164" height="50" loading="lazy"></footer>
    <CustomerModal :open="tutorialOpen" title="Cara Memesan" @close="tutorialOpen = false">
      <ol class="customer-tutorial">
        <li><strong>Pilih menu favoritmu</strong><p>Buka menu, pilih varian dan tambahan, lalu masukkan ke keranjang.</p></li>
        <li><strong>Periksa & buat pesanan</strong><p>Periksa jumlah, catatan, dan total. Isi nama jika diminta, lalu tekan Pesan Sekarang.</p></li>
        <li><strong>Bayar tunai di kasir</strong><p>Tunjukkan nomor pesanan. Bayar sebelum batas waktu yang tampil; kasir memeriksa ketersediaan dan mengonfirmasi pembayaran.</p></li>
        <li><strong>Pantau pesanan</strong><p>Pesanan diproses setelah lunas. Ikuti status pada halaman pesanan.</p></li>
      </ol>
    </CustomerModal>
  </main>
</template>
