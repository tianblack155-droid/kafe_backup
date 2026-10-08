# Runtime Supabase terhubung — 2026-09-17

## Hasil aktual

- Endpoint pooler diperoleh dari Supabase Management API project-scoped, bukan ditebak:
  `aws-0-ap-northeast-1.pooler.supabase.com`, session port `5432` berhasil dipakai.
- Migration `0003_runtime_role.sql` terpasang sebagai
  `20260917035725` / `teraskayumanis_runtime_role`, lalu dibaca balik.
- Akun `tkm_runtime` diberi LOGIN melalui langkah provisioning private terpisah.
  Password acak tidak ada dalam migration, repo, command argument, atau laporan.
- Login actual melalui Session pooler menghasilkan current_user/session_user `tkm_runtime`.
- `sslmode=verify-full` dengan CA Supabase dari URL yang dirujuk source resmi Studio;
  verifikasi hostname/chain berhasil. psql `\conninfo` memastikan TLSv1.3.
- Query `pg_stat_ssl` pada backend DB melalui pooler menampilkan false: itu koneksi
  pooler -> database, bukan socket client -> pooler. Jangan menyebut hasil tersebut
  bukti TLS client tidak aktif; bukti client berasal dari openssl + conninfo verify-full.

## Izin runtime

Role bukan owner, superuser, CREATEDB, CREATEROLE, REPLICATION atau BYPASSRLS, tanpa
outgoing membership dan tanpa schema/database CREATE. Role dapat membaca katalog,
membaca kolom id/role staf, serta mutasi tabel transaksi yang dipakai SQL functions.
Role tidak dapat mengubah akun staf, harga/katalog, settings atau struktur DB.

Runtime adalah credential server tepercaya, bukan role tiap pelanggan. Grant transaksi
memungkinkan akses langsung ke tabel transaksi; otorisasi pelanggan/kasir tetap di Go.
Jangan bagikan password atau menambahkan role ke anon/authenticated. Fungsi tetap invoker.

Semua 16 tabel aplikasi sekarang RLS enabled, dengan policy khusus tkm_runtime dan
GRANT operasi minimum yang digunakan aplikasi. Advisor keamanan Supabase: `lints: []`.
Audit efektif tetap diperlukan setelah perubahan role/policy; advisor kosong bukan
jaminan keamanan seluruh aplikasi.

## Pengujian nyata

- ACL/SQL lifecycle dijalankan SET LOCAL ROLE tkm_runtime di Supabase, rollback.
- Proses Go dengan role runtime dan Supabase asli: `/health` 200, `/ready` 200.
- Nuxt proxy -> Go -> Supabase: menu 200, checkout 201, replay key -> order sama,
  capability tidak ada -> 404, auth kasir tidak ada -> 401, expiry persisted dan
  reorder -> order baru dengan original expired.
- Fixture katalog/meja sementara dipasang via management untuk tes HTTP, lalu dihapus.
  Exact count semua tabel diverifikasi nol kecuali settings default satu baris.
- Review independent migration/permission lulus; regression database/schema CREATE,
  elevated membership, forbidden DDL, NULL-safe assertions lulus di lokal.
- CI juga menjalankan migration0003 + runtime-role test. Expected SQL ERROR dalam
  bagian regression adalah kasus ditolak yang memang diuji; exit keseluruhan harus 0.

Ini menguji runtime dari **VPS Hermes**, bukan New Jersey atau jaringan pelanggan.
Tidak mengklaim login kasir berhasil: hanya penolakan request tanpa token yang diuji
melalui HTTP; transaksi bayar penuh diuji SQL role runtime, belum Auth E2E browser.

## Konfigurasi private lokal

- `backend/.env`: DATABASE_URL verify-full, SUPABASE_URL, SUPABASE_ANON_KEY, bind loopback.
- `frontend/.env`: URL Go loopback dan key public Supabase untuk browser.
- Kedua file mode 600, gitignored; tidak di-commit.
- Password/CA disimpan di `/root/.hermes/secrets/teraskayumanis/` (directory 700).
- API key public bukan service_role. Go tidak memakai token OAuth management.
- Go binary tidak otomatis membaca `.env`: inject melalui process environment atau
  service manager. Private launcher sementara berada di `/tmp/tkm_run_private.py`.
- Go listen `127.0.0.1:8080`, Nuxt `127.0.0.1:3000` untuk verifikasi lokal saja.
  Belum systemd/HTTPS/domain atau auto-start; restart/deploy production belum dilakukan.

## Selanjutnya

1. Buat akun kasir uji yang disepakati melalui Supabase Auth dan tautkan profiles.
2. Uji login/session/role lalu flow customer -> review -> bayar -> selesai melalui browser.
3. Siapkan akses VPS New Jersey (OS/SSH), deploy runtime dan env dengan aman,
   proxy HTTPS + restart policy, kemudian ukur latency dari jaringan cafe.
4. Admin katalog/laporan masih legacy dan tidak mendapat izin lewat role ini.
   Provisioning runtime bukan migrasi semua endpoint admin atau izin memberi service key ke browser.

Evidence redacted: `/root/.hermes/output/tkm-supabase-verification/runtime-*.json`/`.txt`.
Laporan sebelumnya adalah snapshot historis sebelum runtime terhubung.
