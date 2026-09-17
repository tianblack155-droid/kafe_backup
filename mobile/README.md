# Mobile TerasKayuManis

Folder mobile berada **di monorepo yang sama**, bukan repository terpisah.
Aplikasi yang dikerjakan di sini adalah **kasir**, setara peran `/cashier` web:
order masuk -> review ketersediaan/total -> terima tunai -> lunas -> selesai.

Mulai di [cashier/README.md](cashier/README.md). Panduan lengkap untuk teman
pengembang: [cashier/docs/DEVELOPMENT.md](cashier/docs/DEVELOPMENT.md).

- `cashier/`: Flutter Android-first; scaffold iOS ikut disiapkan.
- Backend tetap `../../backend` dari folder aplikasi, web tetap `../../frontend`.
- Tidak ada KDS, tidak ada identitas meja, tidak ada QR scanner di aplikasi kasir.
- WebSocket saat app aktif bukan push background. FCM masih tahap lanjutan.
- Jangan mengubah kontrak backend diam-diam: koordinasikan dalam PR lintas-folder.
