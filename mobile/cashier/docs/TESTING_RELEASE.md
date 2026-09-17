# Testing, CI dan distribusi

## Toolchain dan instalasi

Pin Flutter3.47.4 (Dart3.13.3), JDK17, Android SDK36/build-tools36, NDK28.2.13676358.
Scaffold memakai AGP9.1.0/Kotlin2.4.0/Gradle9.3.1; jangan downgrade/upgrade salah
satu sendiri tanpa menguji plugin. Minimum Android mengikuti Flutter24/API24.

Install Flutter dan Android Studio sesuai OS dari sumber resmi. Setelah SDK Android
tersedia, jalankan `flutter doctor -v`, tinjau lisensi yang diminta dan pilih Android
SDK36. Developer non-root lebih disarankan. Build server headless tidak membutuhkan
Android Studio GUI, tetapi tidak dapat menggantikan uji sentuh/perizinan perangkat.

```sh
cd mobile/cashier
flutter pub get
flutter analyze
flutter test --concurrency=1
dart format --output=none --set-exit-if-changed lib test
flutter build apk --debug --dart-define-from-file=config/preview.json
```

Jika memakai FVM, awali `fvm flutter`/`fvm dart`; `.fvmrc` sudah memuat pin.
APK output `build/app/outputs/flutter-apk/app-debug.apk`. Jangan commit APK ke repo.
Gunakan USB debugging perangkat uji, `flutter devices`, lalu `flutter run -d <device>`.
Jangan mengaktifkan cleartext/global TLS bypass demi emulator. Preview sudah HTTPS.

## Level pembuktian

1. Unit: parsing/null legacy table, guards/state, auth/token, payload/error classification.
2. Widget: login/form, busy guards, input uang/review, dialog confirmation, edit choices.
3. Protocol: native websocket Origin/ready/invalidation/dedup/retry, HTTP serialization.
4. Live opt-in: service Dart memakai preview HTTPS/WSS dan **akun sementara**, bukan
   password user; lihat probe dan `VERIFICATION.md` untuk hasilnya.
5. Android APK compilation: memastikan plugin/platform wiring terbuild.
6. Device acceptance: input keyboard, security storage, lifecycle, audio/permission,
   restart app, offline recovery. Build bukan bukti6; wajib teman lanjutkan.
7. iOS compilation/signing/device hanya di Mac/Xcode; tidak boleh mengklaim lulus dari Linux.

`test/live` harus skip secara default. Jangan memakai akun nyata/customer order sebagai
fixture, jangan menaruh password/token dalam repo/CI output. Gunakan fixture unik,
cleanup ID persis dan verifikasi absen. Nomor order bisa lompat karena sequence;
jangan reset sequence atau hapus data pengguna agar hasil tampak bersih.

## Acceptance perangkat sebelum pilot

### Login dan keamanan
- [ ] Akun kasir valid masuk; akun tanpa role ditolak walau Auth login sukses.
- [ ] Salah password aman, tidak mencetak raw credential/stack.
- [ ] Cold start memulihkan session, refresh token, logout menutup stream dan data layar.
- [ ] Ganti akun tidak melihat draft/order/retry private akun lama.
- [ ] No server key in APK/log/config. Penyimpanan terenkripsi benar-benar berfungsi.

### Order dan transaksi
- [ ] Pelanggan `/menu` tanpa identitas meja -> mobile menerima order baru.
- [ ] Aktif/Riwayat/filter expired/pagination dan detail benar, termasuk order tanpa table.
- [ ] Review qty/varian/addon/hapus/tambah/notes valid; harga final server diperiksa.
- [ ] Tidak bisa bayar sebelum review; stale version/conflict meminta muat ulang.
- [ ] Uang kurang ditolak, integer Rupiah, perubahan total tidak membuat cash salah.
- [ ] Setelah paid, selesai masih perlu konfirmasi terpisah.
- [ ] Double-tap/timeout tidak menghasilkan pembayaran/order ganda.
- [ ] Expired tidak bisa dibayar; reorder baru, old tetap history dan harga diperiksa ulang.
- [ ] Kill app saat respons reorder belum pasti -> reopen/retry identity sama, bukan baru.

### Realtime/lifecycle
- [ ] Dua kasir tidak menimpa versi satu sama lain; conflict ditangani.
- [ ] Network putus, pindah Wi-Fi/data, app pause/resume, server restart -> resync.
- [ ] Event duplicate/burst tidak menumpuk snackbar/bunyi/request.
- [ ] Expiry countdown tidak menjadi satu-satunya payment gate.
- [ ] App tertutup tidak dijanjikan menerima WSS; FCM acceptance terpisah bila dibangun.

## CI

`.github/workflows/mobile.yml` menjalankan pub get, analyze, tests, format dan debug APK.
Tidak berisi Supabase credential; config kosong hanya menghasilkan setup screen pada
binary CI. Build compile tetap valid tanpa login. Jangan menjalankan transaksi preview
pada setiap pull request publik. CI bukan deployment aplikasi/store.

## Release signing

Release signing sengaja **tidak** fallback ke debug keys. Sebelum publish:

1. Konfirmasi pemilik applicationId/bundleId `id.alrizky.teraskayumanis.cashier`.
2. Tentukan distribusi internal/Play Store dan pemilik signing key; tidak otomatis gratis.
3. Buat keystore di tempat private, backup akses terkendali; config local `key.properties`
   gitignored. Tambahkan Gradle signing hanya sesudah key/secret delivery disepakati.
4. Isi version/code di pubspec; semua upgrade APK harus signature compatible.
5. Build release/AAB dengan konfigurasi target yang benar; jangan preview URL tanpa sengaja.
6. Audit permissions/data safety/privacy statement, dependency licenses dan shrink/proguard.
7. Install upgrade di perangkat uji, cek secure storage + pending attempt migration.
8. Simpan checksum artifact dan release notes (source commit, API baseline, known limits).

iOS: Xcode team, signing/capabilities, Keychain entitlement, bundle ID, deployment target,
privacy labels dan device run harus disiapkan di Mac. Scaffold bukan provisioning selesai.

## Troubleshooting

- `Konfigurasi ... belum siap`: salin config, isi anon/publishable key, rebuild; bukan service_role.
- Login sukses Auth tetapi daftar gagal401: mapping profiles.role belum valid/akun revoked;
  minta pemilik verifikasi, jangan admin grant sendiri.
- WSS403: cek WS_ORIGIN exact sans path/trailing slash, WS_URL /ws, server allowlist.
- REST404: API_BASE_URL harus `/api/core/`; `/api/v1/` hanya route internal Go sekarang.
- Response409: baca code, refetch; jangan ganti key untuk menutupi konflik.
- Gradle memory: proyek memakai worker1/heap1536MB untuk VPS; naikkan hanya jika RAM cukup.
- Dependency mismatch: pakai pin Flutter dan lockfile; jangan hapus lockfile untuk trial-error.
- iOS secure storage tidak persistent: cek signing/Keychain capabilities di target Runner.

## Sumber resmi

- https://docs.flutter.dev/install
- https://docs.flutter.dev/platform-integration/android/setup
- https://docs.flutter.dev/deployment/android
- https://docs.flutter.dev/deployment/ios
- https://pub.dev/packages/flutter_secure_storage
