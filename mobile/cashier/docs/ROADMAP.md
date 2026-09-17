# Roadmap handoff dan backlog

Urutan prioritas, bukan janji seluruh fitur sudah dibuat. Status bukti aktual ada di
[VERIFICATION](VERIFICATION.md); pemilik menyetujui scope sebelum pekerjaan tambahan.

## P0 — stabilkan starter di perangkat teman

**Mobile owner**
- Jalankan dengan akun kasir uji yang dibuat pemilik, Android physical device.
- Jalankan semua acceptance login/order/review/tunai/selesai/reorder/lifecycle.
- Tambah integration test perangkat untuk secure-storage cold start dan pending reorder.
- Uji layar kecil/tablet, keyboard/scroll editor, accessibility/text scale/dark contrast.
- Tampilkan nama+nomor order jelas; jangan memasukkan konsep meja kembali.

**Backend owner**
- Akses akun staf per-user, lingkungan fixture aman; tetap least privilege.
- Pastikan API versi lama/baru compatible dan shared-QR business rule tersinkron.

**Done**: bukti device, no duplicate mutation, no credential exposure, semua test hijau.

## P1 — kesetaraan operasional kasir dan polishing

- Review seluruh varian/addon sesuai menu nyata, unavailable/cancel edit semantics.
- Pencarian nomor/nama (tahu batas hanya page lokal sampai search endpoint disepakati).
- Uang diterima/kembalian/konfirmasi dan informasi expired lebih jelas.
- UX permission/role revoked, retry-after429, offline banner dan stale data label.
- Foreground sound setting/visual attention yang tidak spam.
- Pelaporan bug terstruktur tanpa nama/token/order body sensitif.

**Done**: uji kasir café dengan menu nyata, persetujuan pemilik, tidak mengubah transaksi backend.

## P2 — notifikasi background (backend + mobile)

Ikuti [REALTIME_NOTIFICATIONS](REALTIME_NOTIFICATIONS.md). Belum ada Firebase project
atau token endpoint. FCM registration/sender/revocation/rotation adalah satu feature
lintas lapisan, bukan sekadar install firebase_messaging.

**Done**: foreground/background/terminated diuji device nyata, permission deny aman,
user-switch tidak membocorkan order, WSS+FCM dedup, backend delivery retries terpisah.

## P3 — distribusi internal yang terkendali

- Application identity/signing ownership disetujui; debug bukan release store.
- Pin version, changelog, artifact checksum, upgrade/migration tests.
- iOS disiapkan bila dibutuhkan, dengan Mac/team/signing; jangan anggap otomatis.
- Putuskan support minimum OS, cara update dan rollback compatible API.

## P4 — fitur hanya sesudah kebutuhan disepakati

Printer, laporan penjualan mobile, pengelolaan shift, cancellation/refund, admin katalog,
offline mutation queue atau metode pembayaran baru. Masing-masing memerlukan flow/server
rules dan persetujuan terpisah; jangan menambah QRIS/KDS karena schema lama masih memuatnya.

## Not-to-do penting

- Jangan menulis orders/payments langsung ke Supabase.
- Jangan menghitung total final di client atau mengubah paid melalui optimistic UI.
- Jangan memanggil GET customer order dengan Bearer lalu menganggap backend rusak.
- Jangan memakai token di URL WSS atau menyimpan service_role dalam APK.
- Jangan retry POST dengan identity baru saat outcome belum pasti.
- Jangan membuka beberapa socket per widget tanpa cleanup.
- Jangan meminta teman mengembangkan pada main lama tanpa mengambil branch handoff.

## Template PR teman

```md
## Perubahan
- Fitur dan batasnya
## Bukti
- flutter analyze/test/build
- device/OS, langkah reproduksi, video/screenshot tanpa data pribadi
- auth/offline/duplicate/version-conflict cases
## Kontrak
- API berubah/tidak; compatibility dan koordinasi backend
## Risiko / belum diuji
- device, FCM, iOS, signing atau fitur lain yang belum diverifikasi
```
