# Panduan Pengembangan Flutter Kasir

Dokumen handoff untuk teman pengembang. Baca bersama source backend saat kontrak
berubah; dokumentasi bukan izin menambah flow bisnis yang belum disepakati.

## 1. Tujuan produk dan batas peran

Pelanggan scan QR bersama -> web `/menu` -> kirim order. Aplikasi ini dipakai **kasir**
untuk melihat order masuk dan mengelola cash-only. Akun Supabase Auth saja belum cukup:
backend mengecek `profiles.role` termasuk cashier/admin/manager/owner. Gunakan akun
kasir terpisah untuk tiap orang; jangan berbagi password atau membundelkannya dalam APK.

**Tidak ada identitas meja.** Jangan menambah nomor meja wajib, QR per meja, scanner,
table token/cookie, default Meja1 atau join table untuk memutuskan apakah order valid.
Nomor order dan nama pelanggan membantu identifikasi. Riwayat lama boleh menyimpan
referensi meja tetapi itu bukan kebutuhan UI/checkout baru.

**Tidak ada kitchen/KDS.** Jangan menambah status preparing/ready sebagai alur normal.
Tidak ada QRIS, pembayaran online, printer, atau admin menu otomatis dalam scope starter.

## 2. Flow operasional yang tidak boleh dibalik

1. Order pelanggan masuk sebagai `pending` + `unpaid`.
2. Kasir **cek ketersediaan menu**, diskusikan pengganti/jumlah dengan pelanggan,
   kirim revisi dan sepakati **total terbaru sebelum menerima uang**.
3. Backend mengembalikan versi yang sudah direview; baru kasir menerima uang tunai.
4. Konfirmasi lunas menggunakan `expected_version` hasil review dan `received_rp`.
5. Status menjadi `confirmed` + `paid`.
6. Setelah seluruh item diantar, konfirmasi terpisah menjadi `completed` + `paid`.

Review bukan pembayaran. WebSocket bukan penerimaan order oleh staf. Jangan otomatis
menandai paid ketika dialog dibuka atau notifikasi diterima. Uang menggunakan integer
Rupiah, bukan `double`. Total dari server; preview kalkulasi di editor bukan kuitansi final.

### Expiry dan reorder

- Pending/unpaid kedaluwarsa15menit dari `created_at`; gunakan `expires_at` dari server.
- Review tidak memperpanjang timer; order paid tidak expired.
- Expired keluar Aktif, tetap Riwayat. Tidak dihapus atau diaktifkan ulang.
- Pesan ulang menghasilkan order baru, harga/stok divalidasi ulang, timer baru, identity
  request baru. Order lama tetap expired.
- Jika respons POST hilang, **retry percobaan lama**, bukan membuat order kedua.

## 3. Arsitektur yang digunakan

```text
Flutter UI
  -> CashierController (state, lifecycle, serialization)
     -> CashierApi (HTTP cash API, fresh bearer, bounded timeout)
     -> RealtimeClient (native Go WSS, invalidations only)
     -> AuthSession (Supabase Auth login/refresh/signout)
     -> AttemptStore (exact unresolved reorder attempt, encrypted)

Go -> PostgreSQL/Supabase (truth, transactions, authorization)
Go outbox dispatcher -> WSS invalidation -> Flutter fetches REST snapshot
```

Tidak perlu microservices atau state-management framework tambahan untuk starter ini.
`ChangeNotifier` sengaja dipakai agar mudah dibaca/dites; Riverpod/BLoC boleh dievaluasi
bersama sebelum refactor, jangan campurkan beberapa pola pada screen yang sama.

### Struktur folder

```text
lib/main.dart                        bootstrap/config/Supabase secure persistence
lib/app.dart                         root MaterialApp dan lifecycle
lib/core/app_config.dart             compile-time defines dan validation
lib/core/realtime_client.dart        native socket/reconnect/reconciliation
lib/data/auth_session.dart           boundary Auth yang bisa difake saat test
lib/data/secure_store.dart           session + unresolved attempt secure storage
lib/data/cashier_api.dart            REST repository + ApiException
lib/domain/models.dart               immutable order/catalog/draft models + guards
lib/features/auth/                  login UI
lib/features/cashier/                controller, list/detail/editor/dialogs
config/preview.example.json          konfigurasi contoh, TANPA key/password
android/, ios/                      native platform scaffold
 test/core/, test/ui/                unit/protocol/widget regressions
test/live/                          explicit opt-in contract probe; skipped normally
```

Nama tambahan/file UI dapat berkembang; dokumentasikan perubahan public interface.
`pubspec.lock` dipin, `.fvmrc` pin SDK, no generated code dependency. Jangan commit
`.dart_tool`, build, local.properties, define lokal, keystore, Firebase service JSON.

## 4. State dan aturan async

- `signedIn` berarti login **dan** daftar order berizin berhasil, bukan hanya token ada.
- Simpan `orders`, tab, expiredOnly, offset, loading/busy/error, realtimeStatus dan
  pending-attempt state pada controller. Editor/cash field tetap local state.
- Fresh bearer untuk request/reconnect. Role revoked atau session expired harus
  menghentikan akses/menampilkan login/izin error, bukan merender data sebagai update baru.
- Setiap pergantian akun/logout/tab/offset meningkatkan generation. Abaikan respons
  lama yang tiba setelah scope berubah; jangan membangkitkan kembali sesi logout.
- Refresh diserialisasi/coalesced: jika event datang selama fetch, ada trailing refresh.
- Jangan mengganti field editor yang sedang diketik akibat snapshot background.
- Busy guard mencegah double click. Backend version lock tetap pengaman terakhir.
- Pause/background: hentikan socket/reconciliation. Resume: fresh snapshot + reconnect.
  Timer foreground tidak membuktikan background reliability.
- Dispose subscriptions/timers/HTTP client. Jangan menyimpan BuildContext di repository.

## 5. Retry dan penyimpanan

Gunakan `flutter_secure_storage` untuk refresh session dan attempt. Supabase default
SharedPreferences persistence diganti dengan `SecureSessionStorage`. Android backup
dinonaktifkan supaya encrypted material tidak dipulihkan tanpa keystore. iOS Keychain
perlu pemeriksaan entitlement/capability di Xcode sebelum device release.

Attempt reorder harus disimpan **sebelum** HTTP POST dan berisi payload persis,
idempotency key, private order capability. Kunci penyimpanan harus scoped user+environment.
Jika timeout/503/generic409, jangan hapus identity. Logout membersihkan tampilan/socket,
tetapi attempt milik akun lama tidak boleh dipakai akun baru; login akun semula bisa
melanjutkan recovery. UI tidak menawarkan “buat lagi” selama attempt belum pasti.

-201: simpan hasil, hapus pending attempt yang telah pasti, muat ulang daftar.
-409+`checkout_rejected`: validasi ditolak sebelum commit; boleh melepas attempt dan edit.
-409+`idempotency_conflict`: pertahankan, investigasi payload/identity; jangan retry key baru.
-401/429/timeout/transport: pertahankan, pulihkan sesi/tunggu dan retry yang sama.

Jangan simpan password, service_role, database URL, atau token ke log/analytics.
Jangan menelan storage failure lalu mengirim POST tanpa identity durable.

## 6. Pembagian kerja dengan pemilik/backend

**Teman mobile**: UI/UX, controller/service tests, Android device QA, aksesibilitas,
state recovery, notification presentation dan release client.
**Pemilik/backend**: kontrak/server security, schema/migrations, role akun kasir,
FCM registration/sending, deployments, catalog/ops policy.
**Bersama**: status/payment semantics, error codes, version compatibility, acceptance.

Jangan mengubah `backend/` atau production DB hanya agar UI test lolos. Buat proposal
endpoint beserta example request/response dan tes kontrak terlebih dulu. APK terpasang
bisa lebih tua dari web; perubahan server harus backward-compatible atau versioned.

## 7. Cara kerja Git

Branch dasar saat handoff: `refactor/monorepo-go-foundation`, PR masih draft; jangan
mendasarkan fitur pada main lama sebelum pemilik merge. Fetch terlebih dahulu.

```sh
git fetch origin
git switch refactor/monorepo-go-foundation
git pull --ff-only
git switch -c feat/mobile-nama-fitur
# edit + flutter analyze + flutter test + build
# stage hanya perubahan relevan, bukan seluruh output SDK
git add mobile/cashier/lib mobile/cashier/test
git commit -m "feat(mobile): deskripsi fitur"
git push -u origin feat/mobile-nama-fitur
```

PR menjelaskan fitur, video/screenshot device, tests, dampak kontrak, migration (bila
ada) dan batas yang belum diuji. Jangan merge/deploy otomatis tanpa konfirmasi pemilik.

## 8. Selesai berarti terverifikasi

Sebuah fitur baru selesai jika unit/widget tests relevan lulus, analyze bersih,
Android build berhasil, alur diuji di device, error/offline/refresh/logout diperiksa,
dan API contract/backend compatibility terbukti. CI bukan pengganti uji fisik.
Gunakan checklist [TESTING_RELEASE](TESTING_RELEASE.md) dan [ROADMAP](ROADMAP.md).
