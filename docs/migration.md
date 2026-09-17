# Status migrasi: source terpisah, runtime bisnis masih legacy

## Selesai pada branch ini

- Aplikasi Nuxt dipindahkan ke frontend/.
- API TypeScript dipindahkan ke backend/legacy-nuxt/ dan dimuat Nitro dengan serverDir.
- SQL existing dipindahkan ke backend/supabase/.
- Backend Go health/readiness, PostgreSQL pool, config, graceful shutdown dan tests.
- Arsitektur target disalin sebagai backend/arsitektur.md.
- Root npm workspace dan satu package-lock.json.

## Sengaja belum diubah

API Nuxt, RLS, RPC create_order, flow payment lama, role kitchen dan halaman kitchen lama
masih ada untuk menghindari penghapusan fitur/data diam-diam dalam refactor struktur.
Itu **bukan persetujuan scope kitchen**: target baru tetap kasir-only. docs/legacy-task.md
merekam kebutuhan lama dan tidak menggantikan backend/arsitektur.md.

## Berikutnya

1. Tulis test perilaku order/payment legacy, audit schema existing.
2. Tetapkan migration role/status kasir-only dengan strategi data lama.
3. Go auth verifier + permission dan kontrak API.
4. Checkout idempotent + konfirmasi pembayaran atomik + audit/outbox.
5. Pindah satu mutasi per tahap; jangan aktifkan dua penulis dengan business rules berbeda.
6. Hubungkan frontend, kemudian bangun Flutter kasir.
7. Realtime, resync, FCM dan test kegagalan end-to-end.

## Upgrade developer clone

Commit/stash perubahan lokal dahulu, fetch branch baru, lalu npm ci di root. Jangan
memindahkan source dengan copy manual dari branch lama. File .env lama tidak ikut git mv;
pindahkan sendiri ke frontend/.env pada mesin yang memilikinya. Jangan menyalin service key
ke public env atau env Flutter. Go memiliki backend/.env tersendiri.

## Acceptance / batas verifikasi

Build dan typecheck tidak membuktikan transaksi Supabase berjalan. Smoke test tanpa secret
hanya menguji routing, error terkontrol dan process lifecycle. /ready healthy pada unit test
menggunakan test double; koneksi PostgreSQL aktual perlu dijalankan dengan test DB terisolasi.
