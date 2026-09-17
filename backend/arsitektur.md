# TerasKayuManis — Arsitektur Revisi

> Keputusan terbaru: CASH ONLY. Web order pending → bayar tunai di kasir → kasir konfirmasi paid/confirmed → kasir konfirmasi selesai setelah semua item diantar. QRIS, payment gateway, PREPARING/READY terpisah dan refund bukan scope implementasi pertama. Bagian rinci sebelumnya di bawah adalah roadmap; status implementasi ada di `../docs/cash-only-status.md`.

**Versi:** 1.0 — rancangan untuk implementasi bertahap
**Status:** Arsitektur revisi berdasarkan evaluasi dan flow pembayaran yang disepakati. Bukan pernyataan bahwa seluruh fitur sudah diimplementasikan.
**Scope:** Customer Web, Admin Web, Flutter Cashier, Go Backend, PostgreSQL, WebSocket, dan FCM.
**Tidak termasuk:** aplikasi kitchen, Kitchen Display System (KDS), akun/role kitchen, atau channel kitchen.

---

## 1. Keputusan Produk yang Sudah Disepakati

Flow utama:

```text
Pelanggan scan QR meja
        ↓
Pilih menu, varian, add-on, dan jumlah
        ↓
Checkout melalui web
        ↓
Order tersimpan sebagai PENDING_PAYMENT
        ↓
Web menampilkan nomor order dan instruksi menuju kasir
        ↓
Pelanggan membayar order di kasir
        ↓
Kasir memverifikasi pembayaran lalu mengonfirmasi melalui aplikasi
        ↓
Pembayaran tercatat PAID dan order menjadi CONFIRMED
        ↓
Pesanan disiapkan oleh staf secara operasional
        ↓
Makanan/minuman diantar ke meja pelanggan
        ↓
Kasir menandai order COMPLETED setelah pengantaran dikonfirmasi
```

**Pelanggan tidak membayar melalui web pada MVP.** Web membuat pesanan dan menampilkan informasi pembayaran di kasir, bukan memutuskan bahwa pembayaran berhasil.

**Order belum boleh diproses sebelum pembayaran dikonfirmasi kasir.** Konfirmasi adalah tindakan server yang mencatat pembayaran dan mengubah status order secara atomik.

**Tanpa KDS bukan berarti tanpa proses penyiapan makanan.** Proses penyiapan tetap dilakukan staf, tetapi tidak ada perangkat atau aplikasi khusus untuk dapur. Kasir menjadi operator status di sistem. Cara staf menerima instruksi penyiapan di luar aplikasi merupakan prosedur operasional cafe.

---

## 2. Batas Rancangan dan Default MVP

Keputusan di bagian 1 merupakan kebutuhan produk yang sudah disepakati. Default berikut merupakan usulan teknis agar implementasi memiliki batas jelas; dapat diubah sebelum implementasi terkait dimulai.

| Area | Default rancangan MVP |
|---|---|
| Outlet | Satu cafe/outlet, bukan SaaS multi-tenant |
| Order tambahan | Checkout baru menghasilkan order terpisah, walaupun meja sama |
| Pembayaran | Lunas satu kali per order; tidak ada split bill atau partial payment |
| Metode di kasir | Tunai dan QRIS manual, sesuai metode yang benar-benar disediakan cafe |
| QRIS manual | Kasir memverifikasi penerimaan pada aplikasi merchant/alat resmi, bukan screenshot pelanggan |
| Pembatalan pelanggan | Hanya sebelum order dibayar/dikonfirmasi |
| Refund | Pengembalian penuh dengan persetujuan manager/owner; bukan refund otomatis bank |
| Order kedaluwarsa | Opsional dan configurable; durasinya belum ditetapkan |
| Ketersediaan | Flag tersedia/habis per produk/varian/add-on; bukan inventori bahan baku |
| Meja | Nomor meja dan QR aktif/nonaktif; belum ada reservasi atau manajemen okupansi otomatis |
| Perangkat kasir | Android melalui Flutter; perangkat dan printer target ditentukan sebelum integrasi hardware |
| Laporan | Ringkasan order dan pembayaran; bukan sistem akuntansi atau rekonsiliasi settlement QRIS |

**Belum ditetapkan:** durasi expiry, kebijakan order salah meja, perangkat kasir target, kebutuhan printer, periode retensi data, target pemulihan, dan budget hosting bulanan. Nilai tersebut tidak boleh diasumsikan sebagai janji kontrak.

---

## 3. Tujuan dan Prinsip Utama

1. Tidak membuat order ganda ketika pelanggan melakukan retry.
2. Tidak memproses pesanan yang belum dibayar.
3. Tidak kehilangan order hanya karena notifikasi atau koneksi realtime gagal.
4. Tidak mencatat pembayaran dua kali ketika kasir mengulang konfirmasi.
5. Menjaga harga transaksi historis tetap sama setelah harga menu berubah.
6. Memungkinkan web dan aplikasi kasir memakai aturan backend yang sama.
7. Mengutamakan pemulihan data, pengujian, dan operasional yang dapat dipahami.
8. Memulai dengan satu backend, tanpa infrastruktur distribusi yang belum dibutuhkan.

```text
PostgreSQL = sumber data yang sah
Go         = business logic, transaksi, dan otorisasi
REST       = query dan mutasi
WebSocket  = pemberitahuan perubahan
FCM        = pemberitahuan Android
Nuxt       = antarmuka customer dan admin
Flutter    = antarmuka kasir Android
```

Tidak ada status bisnis yang berubah hanya karena menerima WebSocket, FCM, atau ACK transport.

---

## 4. Arsitektur Sistem

```text
Customer Web — Nuxt 4       Admin Web — Nuxt 4       Cashier — Flutter
          │                         │                       │
          └─────────────────────────┼───────────────────────┘
                                    │
                               HTTPS / WSS
                                    │
                        Reverse proxy / TLS / Cloudflare
                                    │
                           Go Modular Monolith
                      ┌─────────────┼─────────────┐
                      │             │             │
                 REST API      WebSocket Hub   Outbox Worker
                      │             │             │
                      └─────────────┼─────────────┘
                                    │
                            PostgreSQL / Supabase
                                    │
                         order, payment, audit, outbox

Outbox Worker ──► WebSocket Hub ──► klien aktif
Outbox Worker ──► FCM ────────────► notifikasi perangkat kasir

Nuxt / Go ──► object storage untuk gambar produk
```

Diagram menunjukkan hubungan komponen, bukan urutan semua request. Setiap query/mutasi berasal dari API ke database; event berasal dari perubahan yang sudah committed.

### 4.1 Go tetap satu aplikasi

Gunakan satu deployable backend dengan modul:

- identity/auth dan permission;
- catalog: produk, kategori, varian, add-on;
- tables dan QR token;
- orders dan pricing;
- payments dan refunds;
- realtime dan outbox;
- devices dan notifications;
- reporting dan audit.

Handler menangani HTTP, service menjalankan business rules, repository menjalankan query. Batas transaksi dimiliki service melalui transaction manager/unit of work. Jangan membuat transaksi terpisah di tiap repository ketika operasi bisnis harus atomik.

### 4.2 Stack

| Lapisan | Pilihan |
|---|---|
| Web | Nuxt 4, Vue 3, TypeScript, Tailwind CSS |
| Web state | Composables; Pinia jika shared state dan realtime memang memerlukannya |
| Backend | Go, net/http, pgx/pgxpool, slog |
| Realtime | Library WebSocket Go yang aktif dipelihara |
| Database | PostgreSQL managed, awalnya Supabase |
| Identity awal | Supabase Auth; Go memverifikasi identitas dan mengotorisasi operasi |
| Mobile | Flutter Android, HTTP client, WebSocket client, secure storage |
| Push | Firebase Cloud Messaging |
| Media | Supabase Storage atau object storage sejenis |
| Deployment | Satu proses Go long-running; Nuxt dapat di-host terpisah |

Tidak perlu downgrade Nuxt 4 untuk mengikuti dokumen lama yang menyebut Nuxt 3. Versi package yang tepat dipilih saat implementasi dan dikunci dalam lockfile.

---

## 5. Scope Antarmuka

### 5.1 Customer web

- Scan QR untuk mendeteksi meja, tanpa registrasi pelanggan.
- Menu per kategori, pencarian, ketersediaan, dan detail produk.
- Varian, add-on, catatan, dan jumlah.
- Ringkasan subtotal, pajak, service charge, dan total sebelum submit.
- Checkout idempotent.
- Nomor order yang mudah disebut ke kasir.
- Instruksi: **“Pesanan belum diproses. Silakan menuju kasir untuk membayar.”**
- Tracking order dan payment status.
- Pembatalan sebelum pembayaran sesuai aturan server.

Estimasi harga di browser bukan otoritas. Jika harga berubah sebelum checkout, server mengembalikan konflik harga agar pelanggan meninjau ulang, bukan diam-diam menagih total berbeda.

### 5.2 Flutter kasir

- Login, logout, status sesi, dan indikator koneksi.
- Daftar order menunggu pembayaran.
- Pencarian berdasarkan nomor order dan meja; pemindaian kode order dapat ditambahkan bila dibutuhkan.
- Detail item, catatan, total, dan meja.
- Verifikasi metode pembayaran, pencatatan uang tunai dan kembalian bila relevan.
- Tombol **“Konfirmasi pembayaran & terima order”**.
- Daftar order yang sudah dibayar dan belum selesai.
- Pembaruan sedang disiapkan, siap diantar, dan selesai.
- Pembatalan yang diizinkan dan pengajuan refund kepada manager/owner.
- Refresh manual, sinkronisasi otomatis, serta notifikasi order baru.

Order belum dibayar harus dipisahkan secara visual dari order siap diproses. Tombol konfirmasi dinonaktifkan saat request berlangsung, tetapi perlindungan sebenarnya tetap idempotency di server.

### 5.3 Admin web

- Katalog, kategori, varian, add-on, harga dan ketersediaan.
- Meja, token QR, regenerasi QR.
- Identitas cafe, pajak dan service charge.
- Akun staf dan permission sesuai kewenangan.
- Riwayat order, pembayaran, refund, dan audit.
- Ringkasan operasional serta laporan sesuai scope MVP.

---

## 6. Order State Machine

| Status | Makna |
|---|---|
| `PENDING_PAYMENT` | Order tersimpan, belum dibayar dan belum boleh diproses |
| `CONFIRMED` | Pembayaran sudah diverifikasi kasir dan order diterima |
| `PREPARING` | Kasir/staf menyatakan pesanan sedang disiapkan |
| `READY` | Pesanan siap diantar ke meja |
| `COMPLETED` | Seluruh item order telah diantar ke meja |
| `CANCELLED` | Order dibatalkan melalui tindakan yang sah |
| `EXPIRED` | Order belum dibayar kedaluwarsa, jika kebijakan expiry diaktifkan |

```text
PENDING_PAYMENT ──payment-confirmation──► CONFIRMED
       │                                    │
       ├──cancel──► CANCELLED               ▼
       └──expire──► EXPIRED              PREPARING
                                            │
                                            ▼
                                          READY
                                            │
                                            ▼
                                        COMPLETED
```

### Invariant wajib

- `CONFIRMED`, `PREPARING`, `READY`, dan transisi penyelesaian hanya dapat dimasuki setelah pembayaran tercatat `PAID`.
- Tidak ada endpoint status biasa yang boleh mengubah `PENDING_PAYMENT` menjadi `CONFIRMED`; gunakan transaksi konfirmasi pembayaran.
- Tidak ada transisi mundur biasa seperti `COMPLETED → PREPARING`.
- `COMPLETED` berarti sudah diantar, bukan pelanggan sudah meninggalkan meja.
- Order baru di meja yang sama tidak boleh membuat order lama berubah atau membuka kembali statusnya.
- Pengembalian dana setelah pengantaran tidak menghapus fakta bahwa order pernah `COMPLETED`; payment state dan audit menyimpan refund.

Untuk MVP, urutan `CONFIRMED → PREPARING → READY → COMPLETED` dipertahankan. Jika cafe ingin melewati tahap tertentu, perubahan harus dinyatakan di aturan server dan tes, bukan hanya membuang tombol di UI.

### Pembatalan setelah pembayaran

Manager/owner dapat membatalkan order berbayar yang belum selesai dengan alasan wajib. Dalam satu transaksi, order menjadi `CANCELLED` dan payment state menjadi `REFUND_PENDING`. Pengembalian dana fisik/merchant dilakukan terpisah dan harus dikonfirmasi sebelum state `REFUNDED`.

Order selesai tidak dibatalkan untuk menghapus riwayat; gunakan prosedur refund/kompensasi dengan alasan dan audit.

---

## 7. Payment State dan Konfirmasi Kasir

State agregat pembayaran MVP:

```text
UNPAID → PAID → REFUND_PENDING → REFUNDED
```

QRIS manual tidak memerlukan state provider `PENDING` karena tidak ada payment gateway. Bila gateway ditambahkan, status attempt/provider dimodelkan terpisah dari agregat pembayaran order.

### 7.1 Operasi konfirmasi pembayaran

```http
POST /api/v1/orders/{order_id}/payment-confirmations
Authorization: Bearer <staff-token>
Idempotency-Key: <unique-key-for-this-confirmation>
```

Contoh request:

```json
{
  "expected_order_version": 1,
  "payment_method": "CASH",
  "amount_received_rp": 100000
}
```

Jumlah uang contoh bukan harga baku produk. Backend selalu membaca `total_rp` dari order; nilai client tidak menjadi dasar total tagihan.

Dalam satu transaksi:

1. Validasi staff aktif dan permission konfirmasi pembayaran.
2. Klaim idempotency key; cek payload hash.
3. Kunci baris order dan verifikasi versi/state.
4. Pastikan order `PENDING_PAYMENT` dan `UNPAID`.
5. Periksa ulang ketersediaan item sesuai kebijakan katalog.
6. Untuk tunai, pastikan uang diterima cukup; hitung kembalian di server.
7. Untuk QRIS, kasir harus sudah memverifikasi pembayaran pada kanal merchant resmi; simpan referensi bila tersedia.
8. Simpan payment record dengan amount sebesar total order.
9. Ubah payment state menjadi `PAID` dan order state menjadi `CONFIRMED`.
10. Tambahkan status history, audit log, dan outbox event.
11. Simpan hasil idempotency lalu COMMIT.
12. Kembalikan snapshot order dan payment yang authoritative.

**Tidak boleh:** update pembayaran sukses tetapi update status order gagal, atau order confirmed tanpa payment record.

### 7.2 Dua kasir menekan konfirmasi

Idempotency melindungi pengulangan satu operasi; row lock/conditional update dan constraint pembayaran melindungi dua operasi dengan key berbeda. Hanya satu pembayaran penuh yang boleh berhasil untuk order MVP. Request lainnya mendapat konflik, lalu aplikasi mengambil state terbaru.

### 7.3 Pembayaran sudah diterima tetapi koneksi putus

Kasir tidak boleh meminta pelanggan membayar ulang hanya karena request timeout. Aplikasi menyimpan key percobaan konfirmasi, menampilkan **“Memeriksa status pembayaran”**, mengambil state server, dan retry dengan key yang sama.

Jika dana sudah diterima tetapi pencatatan server belum berhasil, tampilkan kondisi **perlu rekonsiliasi**, bukan mengklaim transaksi sudah tercatat. Prosedur operasional manager harus tersedia untuk kasus tersebut. Penerimaan uang di dunia nyata tidak dapat dijadikan transaksi database atomik.

### 7.4 Harga dan stok sebelum bayar

Harga order dikunci ketika order dibuat. Pengubahan menu tidak otomatis mengubah order pending. Perubahan pesanan oleh pelanggan dilakukan dengan membatalkan order belum dibayar dan checkout baru pada MVP.

Kasir memeriksa ketersediaan sebelum mengambil pembayaran. Pemeriksaan server saat konfirmasi tetap diperlukan. Jika dana terlanjur masuk namun item tidak tersedia, jangan memaksa order diproses: gunakan rekonsiliasi dan refund yang diaudit.

---

## 8. Identity dan Authorization

### 8.1 Role

- `CASHIER`: order operasional, pembayaran, dan status pesanan sesuai permission.
- `MANAGER`: operasional, katalog, pembatalan berbayar/refund, dan laporan yang diberikan.
- `ADMIN`: konfigurasi dan administrasi teknis sesuai permission eksplisit.
- `OWNER`: otorisasi tertinggi outlet, laporan dan pengelolaan akses.

Tidak ada role kitchen. Pelanggan tanpa akun memakai akses terbatas per order, bukan JWT staf atau role staf `CUSTOMER`.

| Operasi | Pelanggan | Cashier | Manager/Owner | Admin |
|---|---|---|---|---|
| Baca menu publik | Ya | Ya | Ya | Ya |
| Buat order dari QR aktif | Ya | Opsional, di luar flow utama | Opsional | Opsional |
| Baca order | Miliknya saja | Order operasional | Sesuai permission | Sesuai permission |
| Konfirmasi pembayaran | Tidak | Ya | Ya | Hanya jika diberi permission |
| Ubah status operasional | Tidak | Ya | Ya | Hanya jika diberi permission |
| Cancel sebelum bayar | Miliknya saja | Ya | Ya | Sesuai permission |
| Setujui refund | Tidak | Tidak secara default | Ya | Tidak secara default |
| Ubah role staf | Tidak | Tidak | Owner | Permission khusus |

Permission dicek pada REST dan subscription/event routing. Menyembunyikan tombol bukan kontrol akses.

### 8.2 Auth staf

Default migrasi: pertahankan Supabase Auth sebagai identity provider. Go memverifikasi token, issuer, audience, expiry, signing algorithm yang diizinkan, lalu mengecek staff aktif dan permission.

Jangan mempercayai role yang dikirim client. Perubahan role atau pencabutan akun harus mencabut akses realtime dan mutasi sesuai kebijakan sesi. Token yang belum expired bukan izin permanen untuk akun yang dinonaktifkan.

Flutter menyimpan credential di secure storage. Strategi cookie web dan refresh mengikuti integrasi auth yang dipilih; hindari membuat sistem password dan refresh token kedua tanpa kebutuhan nyata.

### 8.3 Pelanggan tanpa login

QR meja berisi token acak yang dapat dirotasi. QR mengidentifikasi meja, bukan memberikan akses ke seluruh order meja tersebut.

Setelah checkout, server menerbitkan capability token acak untuk membaca/membatalkan order tertentu. Simpan hash token di server. Nomor order yang mudah dibaca tidak pernah menjadi credential.

Token customer dikirim melalui mekanisme yang tidak masuk URL/access log bila memungkinkan, misalnya secure HttpOnly cookie atau header token sesuai rancangan sesi. Jika tersedia link berbagi order, perlakukan sebagai bearer capability dengan batas akses yang jelas.

Idempotency checkout harus terikat pada sesi checkout customer yang sama agar retry dapat memulihkan akses ke order tanpa membuat order baru.

QR dapat difoto dan dipakai dari luar cafe. Mitigasi MVP: rate limit, QR/meja aktif, antrean pending yang terlihat kasir, tidak memproses sebelum bayar, dan expiry configurable. Ini mengurangi dampak abuse tetapi bukan bukti lokasi fisik pelanggan.

---

## 9. Data Model

Gunakan PostgreSQL sebagai sumber data. Tabel berikut rancangan konseptual, bukan SQL migration siap produksi.

| Tabel | Tanggung jawab |
|---|---|
| `staff_profiles` | Relasi identity provider, role, status aktif |
| `categories` | Kategori, urutan, status aktif |
| `products` | Nama, harga, foto, kategori, ketersediaan, archive |
| `product_variant_groups` | Grup pilihan dan aturan minimum/maksimum pilihan |
| `product_variants` | Opsi dalam grup, price modifier, ketersediaan |
| `addons` / `product_addons` | Add-on yang diizinkan untuk produk |
| `tables` | Nomor meja, QR token hash, status aktif |
| `orders` | Meja, nomor order, state, payment state, total, version |
| `order_items` | Snapshot nama, harga, jumlah, catatan |
| `order_item_variants` / `order_item_addons` | Snapshot pilihan dan harga tambahan |
| `payments` | Pembayaran penuh, metode, total, penerima, referensi |
| `refunds` | Alasan, persetujuan, jumlah, status pengembalian aktual |
| `order_status_history` | Riwayat transisi dan aktor |
| `idempotency_records` | Scope/key, payload hash, hasil operasi |
| `outbox_events` | Event committed yang harus dipublikasikan |
| `outbox_deliveries` | Retry/status per target pengiriman jika diperlukan |
| `devices` | Device kasir, staff, FCM token, status aktif |
| `audit_logs` | Tindakan sensitif tanpa secret |
| `settings` | Identitas outlet, pajak, biaya layanan, kebijakan order |

### 9.1 Field order penting

```text
id                       UUID internal
order_number             Nomor operasional yang unik dalam scope yang ditetapkan
checkout_session_id      Sesi customer untuk retry dan ownership
customer_access_hash     Hash capability token
customer_name            Opsional/configurable
 table_id                Foreign key ke meja
 table_number_snapshot   Nomor meja saat order dibuat
status                   Order state
payment_status           Agregat payment state
subtotal_rp              Integer rupiah
service_charge_rp        Integer rupiah
 tax_rp                  Integer rupiah
 total_rp                Integer rupiah
pricing_snapshot         Aturan pajak/service dan pembulatan saat checkout
version                  Integer, bertambah pada mutasi authoritative
expires_at               Nullable, jika expiry aktif
created_at / updated_at  timestamptz
```

### 9.2 Constraints

- `quantity > 0`, batas maksimum quantity dan jumlah item per order.
- Nilai uang valid dan total tidak negatif.
- Varian/add-on harus benar-benar milik/diizinkan untuk produk.
- Status valid melalui CHECK atau enum yang konsisten.
- Foreign key dan aturan archive/delete tidak merusak riwayat.
- Unique idempotency key dalam scope identitas dan operasi.
- Constraint pembayaran penuh order MVP tidak dapat tercatat dua kali.
- Nomor order dibuat server; bukan `COUNT(*) + 1` yang rawan race.
- Index sesuai query: order aktif, tanggal, meja, status; item by order; outbox pending; history by order.

### 9.3 Uang dan waktu

Gunakan integer rupiah untuk nilai transaksi MVP. Persentase pajak/biaya layanan memakai representasi fixed-point dan aturan pembulatan eksplisit. Hindari float64 sebagai sumber perhitungan uang.

Gunakan `timestamptz` untuk waktu penyimpanan. Laporan harian dihitung memakai timezone cafe yang dikonfigurasi. Tentukan apakah pajak dikenakan setelah service charge; simpan kebijakan tersebut dalam snapshot dan tes.

### 9.4 Inventory

MVP memakai ketersediaan, bukan stok bahan baku. Jangan mengklaim pencegahan overselling kuantitatif bila database belum menyimpan kuantitas.

Jika inventory kuantitatif ditambahkan: sepakati kapan stok direservasi, masa reservasi, kapan dilepas saat cancel/expire/refund, gunakan row lock atau update kondisional, dan urutkan penguncian untuk menekan deadlock. Fitur ini harus satu transaksi dengan perubahan order terkait.

---

## 10. Idempotency dan Concurrency

Setiap mutasi kritis memiliki `Idempotency-Key`: checkout, konfirmasi pembayaran, cancel, permintaan/pencatatan refund, serta perubahan status yang bisa di-retry.

Perilaku wajib:

- Key sama + payload sama: kembalikan hasil operasi yang sama.
- Key sama + payload berbeda: `409 IDEMPOTENCY_CONFLICT`.
- Dua request serentak: constraint/transaction menentukan satu pemenang.
- Operasi yang rollback tidak meninggalkan record sukses palsu.
- Retry setelah respons hilang dapat menemukan hasil committed.
- Key checkout baru digunakan untuk order baru yang sengaja dibuat, walaupun keranjangnya identik.

Untuk update order gunakan versi yang diharapkan:

```sql
UPDATE orders
SET status = $next_status,
    version = version + 1,
    updated_at = now()
WHERE id = $id
  AND status = $expected_status
  AND version = $expected_version;
```

Contoh bersifat konseptual; service tetap memvalidasi permission dan aturan payment. Nol baris berubah berarti konflik/not found yang harus dibedakan dengan aman, bukan sukses diam-diam.

---

## 11. Transactional Outbox

### 11.1 Pola

```text
HTTP request
     ↓
Authentication / authorization / validation
     ↓
BEGIN
     ├── idempotency claim
     ├── order/payment mutation
     ├── history + audit
     ├── outbox event
     └── idempotency result
COMMIT
     ↓
HTTP response

Worker terpisah dari request lifecycle:
claim committed outbox → publish → retry bila gagal
```

Pembuatan event durable dilakukan **di dalam transaksi**, pengiriman dilakukan **setelah commit**.

### 11.2 Worker

- Mulai dalam proses Go yang sama untuk MVP.
- Claim batch dengan lease/locking yang aman; jangan menahan transaksi database selama request FCM yang lambat.
- Simpan attempts, next_attempt_at, status, dan error yang sudah disanitasi.
- Backoff dan alert untuk delivery yang gagal berulang.
- Worker yang restart dapat mengambil kembali pekerjaan dengan lease kedaluwarsa.
- Pisahkan keberhasilan pengiriman WebSocket dan FCM agar satu kegagalan tidak menghilangkan target lainnya.
- Pantau umur event tertua yang belum diproses, bukan hanya jumlah event.

Semantik yang dituju adalah pengiriman yang boleh berulang, bukan janji exactly-once. Deduplikasi dan state sync tetap wajib. Tidak ada client terhubung bukan alasan memblokir seluruh outbox; order tetap dapat ditemukan melalui snapshot API dan FCM dapat menjadi jalur pemberitahuan.

Socket write berhasil hanya menunjukkan pengiriman ke lapisan koneksi, bukan bukti kasir melihat atau menerima pesanan secara bisnis.

---

## 12. Realtime Protocol

Endpoint awal: `wss://api.example.com/ws`.

### 12.1 Lifecycle

```text
Connect → Authenticate → Authorize subscriptions
→ Buffer incoming events → Load authoritative snapshot
→ Merge by version → Continue live updates
```

Jika autentikasi melalui frame `AUTH`, koneksi belum boleh menerima data bisnis sebelum validasi selesai. Terapkan timeout autentikasi dan batas koneksi belum terautentikasi.

### 12.2 Channels

```text
staff:orders
staff:payments
staff:catalog
order:{internal_order_id}
user:{staff_id}
```

Tidak ada channel kitchen. Subscription berdasarkan permission, bukan role string kiriman client. Scope satu outlet tetap harus eksplisit pada routing; perluasan multi-outlet memerlukan tenant isolation yang dirancang khusus.

Payload disaring per audience. Customer tidak menerima detail internal kasir, referensi pembayaran sensitif, atau order pelanggan lain.

### 12.3 Event envelope

```json
{
  "type": "ORDER_PAYMENT_CONFIRMED",
  "event_id": "<uuid>",
  "schema_version": 1,
  "occurred_at": "<RFC3339 timestamp>",
  "request_id": "<request-id>",
  "data": {
    "order_id": "<uuid>",
    "order_version": 2,
    "status": "CONFIRMED",
    "payment_status": "PAID"
  }
}
```

`schema_version` menjelaskan format pesan. `order_version` menjelaskan versi state order. Keduanya tidak boleh disamakan.

Event utama:

```text
ORDER_CREATED
ORDER_PAYMENT_CONFIRMED
ORDER_STATUS_CHANGED
ORDER_CANCELLED
ORDER_EXPIRED
REFUND_REQUESTED
REFUND_RECORDED
CATALOG_CHANGED
TABLE_QR_CHANGED
```

Gunakan event bisnis untuk transaksi atomik pembayaran dan penerimaan order agar client tidak perlu merangkai dua event terpisah untuk menyimpulkan order sudah sah diproses.

### 12.4 Reconnect dan sinkronisasi

- Exponential backoff dengan jitter dan batas maksimum configurable.
- Heartbeat, read/write deadlines, cleanup koneksi mati.
- Satu koneksi application-level pada Flutter, bukan satu per screen.
- Bounded send buffer; slow client diputus dengan instruksi resync, bukan memblokir hub.
- Resume, reconnect, dan startup selalu memicu sync.
- Tambahkan rekonsiliasi berkala yang ringan; interval ditentukan melalui pengujian beban dan toleransi stale data.

`last_event_id` tidak otomatis memungkinkan replay. Jika replay diimplementasikan, tetapkan event retention, urutan cursor, akses audience, dan response ketika cursor terlalu lama.

### 12.5 Snapshot yang aman

MVP dapat mengambil snapshot daftar order aktif:

1. Subscribe dan mulai buffer event.
2. Ambil snapshot yang lengkap/konsisten beserta metadata sync.
3. Terapkan snapshot.
4. Terapkan buffered event yang versinya lebih baru.
5. Hydrate order dari API jika event tidak membawa state cukup lengkap.

Order completed/cancelled harus hilang dari daftar aktif secara benar. Jangan menghapus data hanya karena tidak ada di satu halaman pagination. Snapshot banyak halaman memerlukan snapshot token/watermark atau kontrak konsistensi yang jelas.

Snapshot terlambat tidak boleh menimpa versi baru. Deduplikasi `event_id` memakai cache berbatas ukuran/umur; jangan membuat map tumbuh tanpa batas.

---

## 13. FCM dan UX Kasir

FCM adalah pemberitahuan, bukan jaminan alarm atau sumber state.

| Kondisi | Perilaku |
|---|---|
| Aplikasi aktif | WebSocket memperbarui daftar; aplikasi mengatur suara/visual |
| Background | FCM menampilkan pemberitahuan sesuai izin dan kebijakan OS |
| Aplikasi dibuka | Ambil state terbaru dari API |
| Notifikasi ditolak/gagal | Order tetap muncul saat sync/refresh |
| Force-stop | Jangan menjanjikan pesan tiba sebelum aplikasi dibuka kembali |

Kebutuhan implementasi:

- Minta izin notifikasi pada perangkat yang memerlukannya.
- Registrasikan token FCM yang terikat staff/device terautentikasi.
- Tangani token refresh, logout, token invalid, dan pencabutan device.
- Deduplikasi FCM dan WebSocket agar event sama tidak membunyikan alarm dua kali.
- Jangan menampilkan nama/detail sensitif berlebihan pada lock screen.
- Notification tap membuka detail berdasarkan ID lalu mengambil state dari API.
- UI menampilkan order pending yang belum ditangani, bukan hanya toast sementara.

Indikator aplikasi membedakan `CONNECTING`, `ONLINE`, `RECONNECTING`, `OFFLINE`, dan `SESSION_EXPIRED`. WebSocket terhubung tidak otomatis berarti database atau mutasi API sehat; tampilkan error API secara terpisah.

---

## 14. REST API

Prefix: `/api/v1`. ID contoh di bawah merupakan ID internal, bukan nomor operasional yang mudah ditebak.

### Public/customer

```text
GET    /menu
GET    /tables/resolve?t={qr_token}
POST   /orders
GET    /orders/{id}             # capability customer atau permission staff
POST   /orders/{id}/cancel      # capability + belum dibayar
```

### Staff

```text
GET    /me
GET    /orders?status=...&cursor=...&limit=...
GET    /orders/{id}
POST   /orders/{id}/payment-confirmations
PATCH  /orders/{id}/status
POST   /orders/{id}/cancel
POST   /orders/{id}/refund-requests
POST   /refunds/{id}/confirm
GET    /sync/orders
POST   /devices
DELETE /devices/{id}
```

### Admin/catalog

```text
GET/POST/PATCH    /products
GET/POST/PATCH    /categories
GET/POST/PATCH    /addons
GET/POST/PATCH    /tables
POST             /tables/{id}/rotate-token
GET/PATCH        /settings
GET              /reports/payments
GET              /audit-logs
```

Rute create/list memakai collection; rute patch memakai `/{id}`. Penghapusan produk yang sudah dipakai transaksi harus berupa archive atau mengikuti constraint historis yang eksplisit.

Login/refresh/logout mengikuti Supabase Auth SDK/integrasi sesi; jangan membuat endpoint auth Go dengan implementasi password paralel secara tidak sengaja.

### Response

```json
{
  "success": true,
  "data": {},
  "request_id": "<request-id>"
}
```

```json
{
  "success": false,
  "error": {
    "code": "ORDER_VERSION_CONFLICT",
    "message": "Pesanan sudah berubah. Muat ulang sebelum melanjutkan."
  },
  "request_id": "<request-id>"
}
```

Status utama: 200/201, 400/422 untuk input, 401 untuk auth, 403 untuk permission, 404 untuk resource tidak tersedia, 409 untuk konflik, 429 untuk rate limit, 503 untuk layanan belum siap.

Kode error minimum: `INVALID_TABLE_TOKEN`, `PRODUCT_UNAVAILABLE`, `PRICE_CHANGED`, `ORDER_NOT_FOUND`, `ORDER_NOT_PAYABLE`, `ORDER_VERSION_CONFLICT`, `IDEMPOTENCY_CONFLICT`, `INSUFFICIENT_CASH`, `REFUND_NOT_ALLOWED`, `AUTH_EXPIRED`, `FORBIDDEN`.

---

## 15. Security dan Database Access

- HTTPS/WSS; allowlist Origin pada handshake browser.
- Origin bukan credential untuk Flutter/native; token dan permission tetap wajib.
- CORS tidak menggantikan WebSocket authorization.
- Proteksi CSRF bila mutasi web memakai cookie.
- Rate limit pada login/integrasi auth, checkout, payment, refund, dan WebSocket messages.
- Batas ukuran request, jumlah item, panjang catatan, frame, dan jumlah koneksi.
- SQL parameterized; jangan membangun query dari string input.
- Jangan log password, access/refresh token, capability customer, atau secret FCM.
- Redaksi QR/capability token dari access logs; header forwarding hanya dipercaya dari proxy yang dikendalikan.
- Upload gambar membatasi ukuran, decoding/content type yang valid, dan lokasi storage.
- Credential migration dan runtime dipisahkan; Go memakai role database berprivilege minimum.
- Kebijakan RLS dan akses melalui Supabase Data API diperiksa secara eksplisit. Jangan mengandalkan RLS jika runtime memakai owner/BYPASSRLS.
- Batasi Data API langsung supaya client tidak dapat melewati business rules Go untuk mutasi transaksi.
- Audit untuk pembayaran, refund, perubahan harga, role, dan QR.

---

## 16. Offline dan Pemulihan

MVP bukan sistem offline-first yang dapat mengesahkan pembayaran tanpa server.

| Gangguan | Perilaku wajib |
|---|---|
| Checkout timeout | Periksa hasil lalu retry dengan key yang sama |
| WebSocket putus | Tampilkan reconnect; REST tetap boleh dipakai jika tersedia |
| API tidak terjangkau | Jangan tampilkan status mutasi berhasil |
| FCM gagal | Tidak memengaruhi order yang tersimpan |
| Go restart | Worker pulih, client reconnect dan sync |
| Flutter restart | Pulihkan sesi/key operasi belum pasti, ambil state server |
| Database tidak siap | Tolak mutasi dengan jujur, tanpa success palsu |
| Kasir sudah menerima uang | Tampilkan kebutuhan rekonsiliasi jika pencatatan belum pasti |

Cache lokal hanya untuk tampilan terakhir, ditandai stale/offline. Mutasi payment/refund tidak boleh diantrekan offline lalu dianggap sukses. Jika offline queue akan ditambahkan, itu scope tersendiri dengan konflik, expiry, dan audit yang diuji.

---

## 17. Deployment dan Operasional

### Awal

- Satu instance Go long-running, satu PostgreSQL managed.
- Nuxt dapat terpisah atau dilayani melalui reverse proxy yang sama.
- TLS melalui konfigurasi proxy/provider yang sesuai.
- Supabase Auth dan object storage tetap dapat dipakai.
- FCM service credential hanya di backend.
- API dan DB di region berdekatan.

### Pool database

Gunakan pgxpool dengan ukuran yang mempertimbangkan limit database, koneksi admin, dan worker. Jumlah socket client tidak berarti jumlah koneksi database.

Pilih direct connection atau session pooler yang sesuai kemampuan jaringan hosting. Jika memakai transaction pooler, periksa kompatibilitas prepared statements dan session state pada konfigurasi aktual.

### Keandalan deployment

- Process supervisor/container restart policy.
- `/health` untuk liveness, `/ready` untuk kesiapan dependency.
- Graceful shutdown: tandai unready, berhenti menerima kerja baru, selesaikan request/transaction aktif dengan batas waktu, lepas lease worker, tutup koneksi, lalu pool.
- Migrasi database terkontrol dan backward-compatible saat rollout.
- Backup terpisah, jadwal retensi dan uji restore.
- Backup media dan konfigurasi penting; dump DB saja bukan backup semua storage.
- Monitoring error, disk, DB connection, outbox lag, dan status worker.

Plan gratis diperlakukan sebagai lingkungan development/pilot dengan batas yang harus diperiksa, bukan SLA production. Budget bulanan disepakati terpisah dari biaya development.

### Scaling

Mulai dari satu instance. Jika dibutuhkan beberapa instance, tambahkan mekanisme fan-out antar hub. Redis Pub/Sub dapat membantu broadcast, tetapi bukan durable queue dan tidak menggantikan outbox/resync.

Jangan menambah Kafka, microservices, atau Kubernetes sebelum ada kebutuhan yang terukur.

---

## 18. Pengujian dan Acceptance Criteria

### Unit

- Kalkulasi harga, pajak, service charge, pembulatan, dan kembalian.
- Pilihan varian/add-on yang valid.
- State machine dan permission.
- Payload idempotency, version comparison dan dedupe.
- Routing event berdasarkan audience.

### Integration PostgreSQL

1. Checkout rollback tidak meninggalkan order/item/payment/outbox parsial.
2. Retry checkout menghasilkan order yang sama.
3. Key sama, payload berbeda ditolak.
4. Dua request checkout bersamaan menghasilkan satu order.
5. Dua kasir membayar order yang sama: hanya satu konfirmasi berhasil.
6. Pembayaran dan `CONFIRMED` committed bersama.
7. `UNPAID` tidak dapat masuk `PREPARING`.
8. Cancel/expiry yang bersamaan dengan pembayaran menghasilkan satu keputusan konsisten.
9. Refund tidak tercatat dua kali dan tidak menghapus riwayat order.
10. Harga historis tidak berubah ketika katalog diperbarui.

### Realtime dan recovery

- Auth gagal, channel tanpa izin, token expired, role dicabut.
- Slow client tidak memblokir hub.
- Crash setelah commit sebelum publish: outbox dipulihkan.
- Koneksi putus selama snapshot; snapshot lama tidak menimpa event baru.
- Order keluar dari daftar aktif ditangani dengan benar.
- Event duplikat tidak menggandakan item atau bunyi.
- FCM gagal, izin ditolak, background, foreground, force-stop.
- Client tidak terhubung tetapi order tetap ditemukan saat sync.

### End-to-end wajib

```text
Scan QR → checkout → pending → ke kasir
→ kasir mencatat pembayaran → confirmed
→ preparing → ready → diantar → completed
```

Uji kasus uang diterima tetapi respons HTTP hilang: tidak ada permintaan bayar ulang dan tidak ada pencatatan ganda.

### Performance

Mulai dengan beban berdasarkan jumlah meja, pengunjung, dan perangkat kasir yang realistis. Ukur p50/p95/p99 API, latensi commit-ke-tampilan, error rate, pemakaian pool, memori, serta reconnect recovery. Target angka ditetapkan setelah baseline perangkat/hosting diketahui; jangan mengklaim SLA dari pilihan Go saja.

---

## 19. Struktur Repository yang Disarankan

```text
TerasKayuManis/
├── web/                         # Nuxt 4 customer + admin
├── backend/
│   ├── cmd/server/
│   ├── internal/
│   │   ├── identity/
│   │   ├── catalog/
│   │   ├── tables/
│   │   ├── orders/
│   │   ├── payments/
│   │   ├── outbox/
│   │   ├── realtime/
│   │   ├── devices/
│   │   ├── reporting/
│   │   └── platform/
│   ├── migrations/
│   └── tests/
├── mobile/cashier/              # Flutter Android
├── contracts/                  # OpenAPI + event schema
├── docs/
│   ├── architecture.md
│   ├── business-flow.md
│   ├── payments.md
│   ├── realtime.md
│   ├── deployment.md
│   └── operations-runbook.md
└── README.md
```

Struktur ini target, bukan instruksi memindahkan repository sekarang. Relokasi folder dilakukan bertahap bersama pembaruan build/deploy.

---

## 20. Roadmap Implementasi

### Tahap 0 — Kontrak bisnis

- Tetapkan default MVP yang memerlukan persetujuan.
- Definisikan peran kasir, penerimaan pembayaran dan pengantaran.
- Hapus scope KDS dari spesifikasi kerja serta draft kontrak sebelum ditandatangani.
- Pilih perangkat kasir dan jalur pengiriman APK.

### Tahap 1 — Fondasi transaksi

- Go project, database access, auth verification, permission, health/readiness.
- Skema order/payment/history/idempotency/outbox.
- Unit dan integration test sebelum integrasi UI.
- Backup dan migration workflow.

### Tahap 2 — Flow web ke kasir

- Pertahankan komponen Nuxt yang masih relevan.
- REST checkout, customer access dan tracking.
- Flutter login, daftar pending, detail, konfirmasi pembayaran, dan status order.
- Flow end-to-end lewat API harus benar walaupun realtime belum aktif.

### Tahap 3 — Realtime

- Outbox worker, hub, channels, lifecycle auth.
- Snapshot/sync, dedupe, reconnect, jitter, manual refresh.
- Test crash dan koneksi terputus.

### Tahap 4 — Push dan UX operasional

- Device/token lifecycle, FCM, permission Android.
- Suara/visual, deduplikasi lintas jalur, pending yang belum ditangani.
- Test perangkat target dan prosedur rekonsiliasi pembayaran.

### Tahap 5 — Pilot cafe

- Load test realistis, uji restore, monitoring dan deploy.
- Dokumentasi pemakaian, staff training, dan acceptance test bersama cafe.
- Perbaiki temuan pilot sebelum menambah inventory atau fitur pembayaran kompleks.

**Reliability tidak ditunda ke tahap akhir.** Transaksi, idempotency, otorisasi, dan outbox dibangun bersama mutasi pertama.

---

## 21. Migrasi dari Versi Nuxt + Supabase

Hasil pemeriksaan repo sebelumnya merupakan baseline, bukan audit commit terkini. Sebelum migrasi dimulai, baca ulang repository aktif dan database yang benar-benar terpasang.

1. Inventarisasi endpoint Nuxt, RPC `create_order`, auth, RLS, dan data existing.
2. Tambahkan tes yang merekam perilaku transaksi lama sebelum memindahkan logic.
3. Tetapkan satu sumber aturan dan satu jalur penulis untuk setiap mutasi.
4. Go boleh sementara membungkus RPC lama dalam fase transisi, tetapi jangan menduplikasi kalkulasi yang berbeda antara RPC dan service baru.
5. Saat pindah ke transaksi Go, migrasikan endpoint dan nonaktifkan jalur mutasi lama secara terkontrol.
6. Existing data/status memerlukan pemetaan dan migration; jangan menganggap semua order lama cocok dengan state baru.
7. Pertahankan format snapshot transaksi historis dan kemampuan membaca order lama.
8. Rilis kontrak API yang kompatibel dengan APK kasir yang masih didukung.
9. Siapkan rollback aplikasi dan strategi database forward-fix; rollback binary tidak otomatis membatalkan migration.

---

## 22. Batas Komersial dan Dokumen

Dokumen ini adalah target arsitektur, bukan estimasi harga, jadwal selesai, atau perluasan scope otomatis.

Nilai draft MoU sebelumnya **Rp700.000** tidak otomatis mencakup rewrite backend Go, aplikasi Android Flutter, FCM, hosting bulanan, integrasi printer, dan pemeliharaan production. Paket pekerjaan, deliverable, garansi, akses source code, dan biaya operasional harus disepakati sebelum implementation commitment.

Draft MoU sebelumnya masih memuat kitchen dan beberapa identitas/pembukaan dari contoh. Draft itu perlu disesuaikan sebelum dipakai sebagai perjanjian final. Pembuatan dokumen arsitektur ini tidak mengubah file MoU atau kode repository.

---

## 23. Ringkasan Keputusan Akhir

- **Customer order di web, lalu bayar langsung di kasir.**
- **Order pending tidak diproses sebelum konfirmasi pembayaran kasir.**
- **Konfirmasi pembayaran dan penerimaan order adalah satu transaksi backend.**
- **Makanan diantar ke meja; kasir menandai selesai setelah pengantaran dikonfirmasi.**
- **Tidak ada kitchen/KDS.**
- **Nuxt 4 + Go modular monolith + PostgreSQL + Flutter kasir.**
- **Supabase Auth dapat dipertahankan untuk mengurangi risiko migrasi identitas.**
- **REST untuk mutasi; WebSocket dan FCM hanya memberitahu perubahan committed.**
- **Idempotency, outbox, permission dan transaksi dibangun sejak awal.**
- **Sync memulihkan state ketika event hilang; ACK bukan penerimaan order oleh kasir.**
- **Satu cafe dan satu Go instance dahulu; scale berdasarkan pengukuran.**
- **Implementasi bertahap, bukan rewrite sekaligus.**

> Keberhasilan sistem diukur dari order dan pembayaran yang benar, dapat dipulihkan, serta jelas bagi kasir dan pelanggan—bukan hanya cepatnya notifikasi muncul.
