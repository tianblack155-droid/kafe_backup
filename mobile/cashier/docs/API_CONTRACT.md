# Kontrak API mobile kasir

Dibaca dari `backend/internal/commerce/{http,orders,review,realtime}.go` dan migration1–5.
Jangan menganggap Supabase REST sebagai API bisnis. Public prefix saat ini
`https://teraskayumanis.alrizky.id/api/core/`, diproxy ke Go `/api/v1/`.
Seluruh UUID di contoh adalah placeholder, bukan data operasional.

## Auth

Login via `supabase.auth.signInWithPassword(email,password)` menggunakan publishable/anon
key. Ambil access token dari session untuk setiap request dan subscription. Refresh
session dikelola SDK; tidak menyimpan password. Backend memvalidasi token melalui Auth
`/auth/v1/user`, lalu `profiles.role` (cashier/admin/manager/owner).

Header staf: `Authorization: Bearer <access-token>`; JSON `Content-Type: application/json`.
Tidak ada cookie wajib, tidak ada table identity. `X-Order-Token` berbeda: private
capability untuk pemilik customer-order, digunakan saat membuat/retry reorder baru.
Jangan menyamakan dengan anon key/staff JWT/QR URL.

## Daftar order

`GET admin/orders?tab=active&offset=0`

- `tab`: active(default) atau history.
- active: pending/confirmed. history: expired/completed/cancelled.
- `status=expired` hanya untuk history.
- offset0..100000, langkah100; server limit100 tetap. Bukan `page`, bukan cursor.
- Response200 array order, termasuk detail item. Tidak ada endpoint detail staf
  khusus `GET orders/:id`: endpoint itu meminta **customer capability**, bukan Bearer.
  Mobile menampilkan detail dari snapshot array dan melakukan refetch list saat berubah.
- Hindari mengira kurang dari100 item berarti seluruh histori selamanya; itu page akhir
  untuk query saat ini. New event belum tentu masuk page yang sedang ditampilkan.

Contoh struktur (nilai ilustrasi, bukan respons live):

```json
{
  "id":"<uuid>","order_number":"A123","customer_name":"Pelanggan",
  "table_id":null,"tables":null,"status":"pending","payment_status":"unpaid",
  "payment_method":"cash","version":2,"reviewed_version":2,
  "expires_at":"<ISO8601 UTC>","created_at":"<ISO8601 UTC>","total":10000,
  "order_items":[{
    "id":"<uuid>","product_id":"<uuid>","product_name":"Teh",
    "quantity":2,"unit_price":5000,"addons_total":0,"subtotal":10000,
    "variant_ids":[],"addon_ids":[],"notes":"",
    "order_item_addons":[]
  }]
}
```

Snapshot juga berisi subtotal/discount/tax/service_charge dan field lain. Abaikan field
tambahan yang tidak dibutuhkan; jangan drop order karena tables null. Integer Rupiah.

## Menu untuk review

`GET menu` public, response200 `{settings,categories,products}`.

Product: id,name,price,is_available,variants[],addons[]. Variant:
id,name,group_name,price_modifier,is_available. Addon: id,name,price,is_available.
**Pilih satu variant per available group**, tidak boleh duplicate group; setiap available
group wajib diisi. Addon harus terkait product dan available, tidak boleh duplicate.
Menu/catatan review dimuat fresh sebelum revisi. Jangan mengganti menu hilang diam-diam.
`settings.require_customer_name` mengatur nama saat membuat order/reorder.

## Review/revisi sebelum pembayaran

`POST orders/<uuid>/review`

```json
{"expected_version":1,"items":[{"product_id":"<uuid>","quantity":2,"variant_ids":[],"addon_ids":[],"notes":"tanpa es"}]}
```

Server menghitung harga, mengubah version dan reviewed_version bersama. Tetap pending/unpaid;
expires_at tidak diperpanjang. Response200 snapshot order. Maksimal50 baris, qty1..50,
variant/addon maksimal20 masing-masing, notes disimpan maksimal200 karakter.
Frontend dilarang mengirim total/subtotal buatan sendiri. Stale/expired409 -> muat ulang,
kasir cek ulang bersama pelanggan sebelum menerima uang.

## Konfirmasi tunai

`POST orders/<uuid>/confirm-cash`

```json
{"expected_version":2,"received_rp":20000}
```

Hanya reviewed_version==version, pending/unpaid, belum expired. `received_rp` >=total.
Response200 snapshot confirmed/paid + change_rp. Server membatasi nilai tunai maksimum.
Retry exact version+received sama aman; berbeda menghasilkan konflik. Tidak boleh
mengulang penagihan karena respons hilang: fetch status dahulu dan beri instruksi kasir.
Jangan auto-retry POST dengan input yang sudah berubah. Dialog harus menegaskan uang
sudah diterima dan total telah disetujui, bukan sekadar “Yakin?”.

## Konfirmasi selesai

`POST orders/<uuid>/complete` body `{}`. Hanya order paid/confirmed; setelah semua
item diserahkan/diantar. Response200 completed/paid. Ini terpisah dari pembayaran.

## Pesan ulang expired

`GET orders/<uuid>/reorder` (Bearer staf) ->200:

```json
{"customer_name":"Pelanggan","payment_method":"cash","items":[{"product_id":"<uuid>","quantity":1,"variant_ids":[],"addon_ids":[],"notes":""}]}
```

GET hanya menyiapkan draft, tidak membuat order. Mobile ambil katalog terbaru, revisi
dan konfirmasi. POST `orders` dengan draft baru, **tanpa table_token**:

```text
Idempotency-Key: <random UUID, panjang16..128>
X-Order-Token: <private random capability, panjang24..256>
```

Response201 (termasuk retry) snapshot baru pending/unpaid. Simpan payload/key/capability
secara durable dan scoped akun sebelum POST. Retry harus byte-semantically sama JSON,
jangan mengganti key ketika respons belum pasti. Jangan mengubah timer/order lama.

## Error dan jaringan

Bentuk umum `{ "error":"...", "code":"...optional" }`. Jangan expose raw stack,
request header atau Supabase exception penuh di UI. POST tidak otomatis diretry.

-400: payload/type/method invalid. Periksa serializer/schema.
-401: auth tidak valid **atau** role staf tidak diterima. Jangan anggap login UI saja cukup.
-403: forbidden/Origin policy/DB permission. Jangan memperlebar grants sebagai shortcut.
-404: tidak ditemukan/ownership tidak valid. Bukan alasan mencoba capability berbeda.
-409: stale/review gate/expired/validation. REST refetch sebelum aksi berikut.
-409 code `checkout_rejected`: checkout baru pasti tidak commit; boleh hapus attempt.
-409 code `idempotency_conflict`: key/body/token beda; pertahankan identity dan investigasi.
-429: backend budget global300request/menit, `Retry-After:60`; batas saat ini bukan per device.
-503/timeout/network: hasil mutasi bisa tidak pasti. Jangan menampilkan sukses lokal.

Backend REST context8detik, BFF15detik, client timeout bounded; jangan memicu paralel
polling berlebihan. Event coalescing dan batas pagination membantu menjaga budget.
Semua retry gunakan backoff, tidak loop ketat.

## Referensi source dan aturan kompatibilitas

- `../../../backend/internal/commerce/http.go`: routes/menu/budget.
- `../../../backend/internal/commerce/orders.go`: auth/list/payment/checkout.
- `../../../backend/internal/commerce/review.go`: review/reorder/expiry.
- `../../../backend/migrations/0002_order_review_expiry.sql`: gate/transactions.
- `../../../backend/migrations/0005_shared_qr_checkout.sql`: tableless snapshot/staging.

Paths di atas relatif `mobile/cashier/`; dari file docs naik satu tingkat tambahan.
Server adalah sumber kebenaran. Bila API berubah, update test contract, docs dan changelog,
jangan sekadar menyesuaikan parser sehingga error tidak terlihat.
