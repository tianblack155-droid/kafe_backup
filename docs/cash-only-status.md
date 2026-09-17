# Cash-only implementation — status dan gate

> **Koreksi QR:** meja tidak mempunyai identitas. Satu QR menuju `/menu`; tidak ada scan
> tambahan, pilihan meja, cookie meja, atau default Meja1. Migration5 menghapus
> ketergantungan meja untuk checkout/review/reorder; data lama dipertahankan.
> Lihat [shared-qr-checkout](shared-qr-checkout.md). Catatan Meja1 di bawah bersifat historis.

> Update 2026-09-17: preview telah dideploy ke VPS New Jersey dengan HTTPS/systemd.
> [Customer](https://teraskayumanis.alrizky.id/menu) dan [kasir](https://teraskayumanis.alrizky.id/cashier).
> WebSocket + shared-QR checkout sudah live (`76b0976`); browser Supabase Auth asli dengan akun sementara lolos.
> Akun user tidak disentuh. Satu menu uji Es Teh Manis (Uji), Rp5.000 tersedia. Meja tidak diperlukan.
> [Kontrak dan bukti realtime](realtime-websocket.md).
> [Bukti deployment dan batas pilot](../deploy/README.md).

## Update: review sebelum bayar, expired dan pesan ulang

Migration `0002_order_review_expiry.sql` setelah 0001 menambah:
- Batas bayar tepat created_at + 15 menit; hanya pending/unpaid yang expired.
- Worker setiap 5 detik menyimpan expiry/history/outbox. Read dan payment juga mengecek
  deadline; pembayaran tidak bisa lolos walau worker tertunda. Saat server mati, sweep
  mengejar ketertinggalan saat hidup kembali. Record tidak dihapus.
- Tab Aktif/Riwayat (termasuk filter Expired) dengan halaman 100 baris, offset maksimum 100000.
- Kasir cek ketersediaan, revisi jumlah/menu/pilihan dan setujui bersama pelanggan SEBELUM
  menerima uang. `/review` menyimpan harga server dan audit before/after. Revisi tidak
  memperpanjang timer. Payment wajib membawa versi yang sudah direview; versi usang ditolak.
- Pesan ulang pelanggan -> keranjang harga terbaru; kasir -> editor draft -> order baru.
  Keduanya memakai key baru untuk order baru dan mempertahankan key saat retry. Order lama
  tetap expired. Menu/pilihan yang tidak tersedia harus diganti; tidak dibuang diam-diam.
- Review memakai priced staging order dalam transaksi dan menghapus staging sebelum commit;
  nomor urut dapat memiliki gap. Order ID/nomor pelanggan asli tetap sama saat revisi.
- Baris legacy sebelum migration tidak memiliki snapshot ID pilihan yang andal; pilihan
  wajib diseleksi ulang oleh kasir. Saat memasang migration live, target cloud masih kosong.

Verifikasi: SQL lifecycle/review/expiry + HTTP integration + race concurrent review/payment,
expiry setelah menunggu row lock, worker shutdown. Chromium menjalankan Nuxt -> Go ->
PostgreSQL lokal; Auth service **mock**. Bukan bukti Supabase live.

Review independen final melalui proses Hermes terpisah lulus: seluruh perubahan diperiksa,
empat temuan awal diperbaiki dan enam tes regresi perilaku ditambahkan (17 tes frontend total).
Approval ini hanya untuk perubahan kode, bukan Supabase live/deployment. Subagent provider
lama gagal 503; reviewer pengganti memakai provider aktif tanpa mengubah konfigurasi global.

Browser runner opsional: install Playwright terpisah dan set `PLAYWRIGHT_MODULE` ke index.mjs,
kemudian `node scripts/browser-order-flow.mjs` setelah build Go + Nuxt Node. Runner memakai
DB lokal disposable bernama `teraskayumanis_test` dan port 4591–4593, tidak untuk production.

Kontrak baru: POST `/orders/{id}/review` `{expected_version,items}`, POST confirm-cash
`{received_rp,expected_version}`, GET `/orders/{id}/reorder` (capability token pelanggan atau
Bearer kasir) mengembalikan draft, bukan langsung membuat order.

Bagian fondasi berikut adalah catatan tahap sebelumnya; update di atas mengunggulinya.


## Flow aktif baru

Web `/menu` dan `/cart` memakai `/api/core/*`, proxy same-origin ke Go `/api/v1/*`.
Order `pending/unpaid` -> kasir `/cashier` login Supabase -> konfirmasi uang diterima
-> `confirmed/paid` -> setelah semua item diantar, konfirmasi `completed/paid`.
QRIS tidak tersedia pada checkout. `/admin/orders` dan `/admin/kitchen` mengarah ke
halaman kasir. API order lama diblokir 410 untuk menghindari dua penulis transaksi.

`pending` adalah representasi teknis PENDING_PAYMENT pada arsitektur. Tidak ada langkah
PREPARING/READY terpisah untuk flow cash-only yang disepakati terbaru.

## Implementasi

- Go menu/table, checkout, customer order capability, daftar kasir, confirm-cash, complete.
- Go memverifikasi Bearer token ke Supabase Auth `/auth/v1/user`, lalu mengecek profiles.
- SQL functions schema `tkm` (bukan public RPC) menjalankan transaksi checkout/payment/completion.
- Harga dari database; snapshot item/add-on; pilihan varian/add-on divalidasi.
- Idempotency checkout tersimpan dengan payload dan SHA256 token akses.
- Konfirmasi bayar memakai row lock dan satu payment per order; retry dengan nominal berbeda konflik.
- Riwayat dan outbox event tersimpan bersama mutasi. Outbox publisher + WebSocket sudah dibuat; polling/reconciliation tetap cadangan. FCM belum dibuat.
- Budget request global per proses 300/menit sebagai proteksi awal (bukan limiter per pelanggan/production final).
- Daftar kasir dibatasi 100 order terbaru; pagination operasional lanjutan belum dibuat.

## Database target baru

`backend/migrations/0001_cash_only.sql` hanya untuk project baru dengan public kosong.
JANGAN jalankan `backend/supabase/migrations/0001_init.sql` legacy pada project ini.
Migration baru tidak punya policy staff_all atau role kitchen. Semua public tables RLS enabled,
no anon/authenticated policies. Runtime role direct DB yang terbatas harus diprovision dengan
grant dan policy server-only yang sesuai; jangan menjalankan production sebagai DB owner.
Tidak ada akun/password staf atau menu asli yang ditambahkan otomatis.

## Bukti pengujian

PostgreSQL 16 test DB lokal: cash lifecycle, total/kembalian, retry, gate belum lunas,
history/outbox. SQL test transaksi di-rollback. Go HTTP integration memakai PostgreSQL nyata
lokal dan **test server Auth**, bukan login Supabase nyata. Unit/race/vet/build lulus.
Typecheck + tes struktur/UI + build Nuxt Node/Vercel lulus. Smoke process Go/Nuxt lulus.

## Supabase: catatan migration/runtime tahap sebelumnya

OAuth sudah diotorisasi ulang. Migration 0001 dan 0002 terpasang dan dibaca balik pada
2026-09-17; tes cash lifecycle, review/expiry dan fresh reorder lulus di PostgreSQL Supabase
melalui MCP. Semua baris fixture di-rollback; hanya settings default tersisa.
Detail bukti, ACL, dan batas verifikasi: [laporan Supabase](supabase-verification-2026-09-17.md).

Update runtime: role terbatas `tkm_runtime` sudah diprovision; Go/Nuxt terhubung ke Supabase
via Session pooler + TLS verify-full. Env lokal mode600/gitignored. HTTP checkout, expiry,
reorder dan penolakan tanpa token lulus. [Laporan runtime](runtime-supabase-2026-09-17.md).
Update: full browser -> Go -> Supabase Auth/payment dan WSS diuji dengan akun sementara;
lihat realtime-websocket.md. Credential akun user tidak digunakan.
MCP login bukan pengganti credential aplikasi. Jangan taruh secret dalam chat/GitHub.

## Sebelum merge main

- Selesai: OAuth tulis, migration live dan pengujian SQL rollback. Bukan browser E2E.
- Selesai: runtime DB role terbatas, deny DDL/catalog/staff writes, TLS dan HTTP live.
- Test data katalog dan akun kasir dibuat dengan identitas test eksplisit.
- Concurrency checkout/payment, token ownership dan error cases ditambah/dijalankan.
- Browser E2E ke Supabase nyata, cleanup test fixture, preview deploy verified.
- Review keamanan independen. PR tetap draft sampai gate selesai.

## Run lokal (test DB terisolasi)

```bash
psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -1 -f backend/migrations/0001_cash_only.sql
psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -1 -f backend/migrations/0002_order_review_expiry.sql
psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/cash_lifecycle.sql
psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f backend/tests/order_flow.sql
cd backend
TEST_DATABASE_URL="$TEST_DATABASE_URL" go test -race ./...
```

`TEST_DATABASE_URL` harus database disposable khusus tests. Jangan menunjuk production:
Go integration tests membuat dan membersihkan fixture, SQL lifecycle memakai rollback.

Go runtime env: DATABASE_URL, SUPABASE_URL, SUPABASE_ANON_KEY.
Nuxt: NUXT_GO_API_URL (server-only), NUXT_PUBLIC_SUPABASE_URL dan
NUXT_PUBLIC_SUPABASE_ANON_KEY (auth browser). Legacy admin catalog masih memerlukan
server env lama; schema/storage/admin belum diuji menyeluruh dengan target baru.
