<script setup lang="ts">
import type { StaffRole } from '#shared/types'

const LINKS: { to: string; label: string; icon: string; roles: StaffRole[] }[] = [
  { to: '/admin', label: 'Dashboard', icon: 'clock', roles: ['admin', 'manager', 'kitchen', 'cashier'] },
  { to: '/admin/orders', label: 'Pesanan', icon: 'bag', roles: ['admin', 'manager', 'kitchen', 'cashier'] },
  { to: '/admin/kitchen', label: 'Dapur', icon: 'menu', roles: ['admin', 'manager', 'kitchen'] },
  { to: '/admin/products', label: 'Produk', icon: 'pencil', roles: ['admin', 'manager'] },
  { to: '/admin/categories', label: 'Kategori', icon: 'pencil', roles: ['admin', 'manager'] },
  { to: '/admin/addons', label: 'Add-on', icon: 'plus', roles: ['admin', 'manager'] },
  { to: '/admin/tables', label: 'Meja & QR', icon: 'qr', roles: ['admin', 'manager'] },
  { to: '/admin/settings', label: 'Pengaturan', icon: 'refresh', roles: ['admin', 'manager'] }
]

const { me, load, logout } = useAdmin()
const drawerOpen = ref(false)
const route = useRoute()

onMounted(load)

const visibleLinks = computed(() => LINKS.filter((l) => !me.value || l.roles.includes(me.value.profile.role)))
</script>
