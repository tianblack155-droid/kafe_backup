# Gate sebelum merge / deployment

Status pemeriksaan aktual:

- Supabase project aiptdjypuccoakyfvdyl dapat diakses melalui MCP.
- Schema public kosong dan list_migrations kosong pada pemeriksaan.
- DATABASE_URL backend, secret/service key Nitro dan public auth env belum tersedia pada worktree.
- Tidak ada deployment GitHub atau webhook repo yang terdaftar saat diperiksa. Ini tidak membuktikan tidak ada integrasi provider di luar GitHub.
- Go baru health/readiness. API order/payment masih Nitro; bukan migrasi bisnis selesai.

## Konfigurasi deployment

### Vercel web

Root Directory harus root repository (`.`), Framework Preset Other (framework:null).
vercel.json memakai npm ci dan npm run build:vercel. Script membangun Nuxt dengan
NITRO_PRESET=vercel dan memindahkan output Build Output API ke .vercel/output root.
Build lokal preset Vercel berhasil; provider belum dihubungkan/dideploy.
Jangan mengubah semua /api ke Go karena Go tidak memiliki endpoint bisnis.

Isi kelima env di frontend/.env.example. URL dan anon/publishable key dapat sama
untuk versi server dan public. Service key hanya NUXT_SUPABASE_SERVICE_KEY.

### Render Go

render.yaml menggunakan free, Docker context ./backend, main, dan autoDeployTrigger: off.
Deployment manual diperlukan sampai migration bisnis benar-benar lulus. /health hanya
liveness; periksa /ready terpisah. DATABASE_URL harus disimpan sebagai secret Render.
Tidak ada layanan dibuat/biaya diaktifkan oleh penambahan blueprint ini.

## Blocker bisnis yang ditemukan

- API admin legacy mengizinkan pending -> preparing sebelum paid.
- Update status/payment/history bukan satu transaksi database.
- RLS staff_all legacy memberi seluruh staff hak tulis ke profiles dan transaksi,
  sehingga permission di API dapat dilewati oleh client authenticated.
- Blueprint SQL lama tidak boleh diaplikasikan apa adanya ke Supabase baru.
- Konfigurasi Nuxt sebelumnya tidak mendeklarasikan private supabaseAnonKey walaupun
  requireStaff membacanya; telah ditambahkan, public env juga diperjelas.

## Langkah berikut yang wajib sebelum klaim E2E / merge rilis

1. Sepakati migration bisnis Go atau pengerasan legacy sebagai langkah transisi.
2. Tulis schema target + policy/RPC yang membatasi privilege, bukan staff_all.
3. Implementasikan atomic konfirmasi pembayaran dan payment gate dengan test concurrency.
4. Pasang credential runtime secara aman (bukan chat/repo); akses MCP bukan credential aplikasi.
5. Uji customer -> order pending -> login kasir -> paid/confirmed -> completed melalui HTTP
   menggunakan Supabase nyata dan test fixtures yang dibersihkan.
6. Recheck deployment preview dan CI sebelum main.

Belum dilakukan: migration schema, pemasangan akun test, DB writes, transaksi E2E,
implementasi Go order/payment, atau perubahan deployment provider.
