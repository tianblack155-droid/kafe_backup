# TerasKayuManis Kasir — Flutter

Fondasi aplikasi **kasir**, bukan aplikasi pelanggan dan bukan KDS. Pengerjaan lanjutan
oleh teman pengembang dilakukan di folder ini pada monorepo `zDarkx1/TerasKayuManis`.
Dokumen utama: **[Panduan Pengembangan](docs/DEVELOPMENT.md)**.

## Mulai cepat

### Demo lokal tanpa akun/key

```sh
flutter run -t lib/main_demo.dart
flutter build apk --debug -t lib/main_demo.dart
```

Demo memakai layar kasir yang sama, menu dummy dan transaksi dalam memori. Ada order
pending, lunas dan expired untuk mencoba review, tunai, selesai dan reorder. Label
DEMO selalu terlihat. Data reset saat proses app ditutup; tidak memakai jaringan,
Supabase atau secure storage. Ini uji UI, bukan bukti integrasi web/realtime/recovery.
Build live tetap memakai `lib/main.dart` dan konfigurasi preview di bawah.
APK demo memakai applicationId `id.alrizky.teraskayumanis.cashier.demo`, agar tidak
menggantikan instalasi live. Di Windows sesi ini, SDK tersedia sementara di
`C:\Users\gugum\AppData\Local\Temp\opencode\flutter-3.47.4`; belum ditambahkan ke PATH.

```powershell
# Jalankan dari mobile/cashier di terminal Windsurf:
& "$env:LOCALAPPDATA\Temp\opencode\flutter-3.47.4\bin\flutter.bat" run -t lib/main_demo.dart
```

Toolchain yang dipin: **Flutter3.47.4 / Dart3.13.3**, JDK17, Android SDK36.
`.fvmrc` opsional untuk FVM; `pubspec.lock` wajib ikut Git. Native Android/iOS saja,
Flutter Web tidak didukung karena transport WSS native memakai `dart:io` dan Origin.

```sh
git clone https://github.com/zDarkx1/TerasKayuManis.git
cd TerasKayuManis
git switch refactor/monorepo-go-foundation
git switch -c feat/mobile-cashier-next
cd mobile/cashier
flutter --version
flutter doctor -v
flutter pub get
```

Salin `config/preview.example.json` menjadi `config/preview.json` (gitignored):

```sh
# macOS/Linux
cp config/preview.example.json config/preview.json
# PowerShell
# Copy-Item config/preview.example.json config/preview.json
```

Isi **SUPABASE_ANON_KEY** dengan publishable/anon key project dari pemilik, atau
Dashboard Supabase -> Project Settings -> API Keys. Jangan memakai `service_role`,
secret key, password database, atau token MCP. Key publik bukan izin kasir.
Akun tetap harus login Supabase Auth dan memiliki role staff yang diterima backend.
Jangan memasukkan email/password pengguna ke file defines.

```sh
flutter analyze
flutter test --concurrency=1
flutter devices
flutter run --dart-define-from-file=config/preview.json
# APK internal debug, bukan rilis Play Store:
flutter build apk --debug --dart-define-from-file=config/preview.json
```

Tanpa konfigurasi valid app menampilkan petunjuk, tidak berpura-pura terhubung.
Konfigurasi dibaca pada compile time; ubah config lalu jalankan ulang build, bukan
hanya hot reload. `--dart-define` bukan tempat rahasia server: isinya dapat diekstrak
APK. Identitas pengembangan `id.alrizky.teraskayumanis.cashier`; pemilik harus
mengonfirmasi sebelum distribusi/store, tidak ada signing produksi yang disiapkan.

## Baca berurutan

1. [DEVELOPMENT](docs/DEVELOPMENT.md): scope, flow bisnis, struktur, coding, pembagian kerja.
2. [API_CONTRACT](docs/API_CONTRACT.md): endpoint/payload, auth, status, error dan retry.
3. [REALTIME_NOTIFICATIONS](docs/REALTIME_NOTIFICATIONS.md): WebSocket aktif, lifecycle,
   reconnect, batas notifikasi dan roadmap FCM.
4. [TESTING_RELEASE](docs/TESTING_RELEASE.md): tes, perangkat, build/signing/CI, acceptance.
5. [ROADMAP](docs/ROADMAP.md): pekerjaan lanjutan, dependensi backend dan definisi selesai.
6. [VERIFICATION](docs/VERIFICATION.md): hasil tool yang benar-benar dijalankan pada handoff.

## Endpoint preview

- REST **`https://teraskayumanis.alrizky.id/api/core/`** (trailing slash).
- WSS **`wss://teraskayumanis.alrizky.id/ws`**.
- Origin WSS **`https://teraskayumanis.alrizky.id`** (native harus mengirim header ini).
- Auth **`https://aiptdjypuccoakyfvdyl.supabase.co`**.
- Web kasir pembanding: `https://teraskayumanis.alrizky.id/cashier`.
- Pelanggan: satu QR bersama ke `/menu`. **Tidak ada identitas meja/table_token.**

Jangan langsung memakai `/api/v1/` di domain publik: sekarang route publik melalui
BFF `/api/core/`. Jangan bypass Go dengan `supabase.from('orders').update(...)` atau
subscribe Postgres Changes: otorisasi/mutasi/order event milik Go.

## Batas handoff

Starter ditujukan untuk pengembangan dan uji internal. FCM/background/killed-app
notification, printer Bluetooth, offline mutations, QRIS, admin katalog dan release
signing **bukan fitur jadi**. WebSocket hanya dapat diandalkan ketika app aktif;
foreground return selalu ambil snapshot. iOS perlu Mac/Xcode/signing dan uji device
terpisah. Lihat VERIFICATION untuk membedakan code, tests, build dan uji perangkat.
