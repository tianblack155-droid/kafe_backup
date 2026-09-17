# TerasKayuManis — frontend dan legacy setup

> Keterangan di bawah adalah fitur **versi lama** yang dipertahankan selama refactor.
> Target baru kasir-only ada di [arsitektur backend](../backend/arsitektur.md).
> Kitchen lama belum dihapus dalam perubahan struktur ini; bukan bagian target baru.
> Install dari root monorepo: `npm ci`, kemudian `npm run dev`.
> Environment Nuxt berada di `frontend/.env`; schema legacy berada di
> `backend/supabase/migrations/0001_init.sql`. Panduan lama di bawah bukan panduan migrasi Go.


Sistem pemesanan digital untuk cafe: customer order via QR meja, dapur melihat pesanan realtime, admin mengelola menu/meja/pesanan.

**Stack:** Nuxt 4 + Supabase (PostgreSQL, Auth, Storage, Realtime) + Tailwind CSS v4. Tanpa Pinia/VueUse/shadcn — `useState` + CSS classes menutupi kebutuhan dengan lebih sedikit kode.

## Fitur

**Customer** (mobile-first): QR table detection (`/menu?t=<token>`), kategori, best seller, pencarian, product detail (bottom sheet) dengan varian per-grup (Ukuran/Gula/Es), add-on, catatan, harga dinamis, keranjang + checkout dalam satu halaman, tracking status pesanan (poll 5 detik) dengan nomor pesanan ramah manusia (A101, A102, ...).

**Admin**: login email/password + RBAC (admin/manager/kitchen/cashier), dashboard statistik harian, manajemen pesanan (status + pembayaran terpisah, transisi tervalidasi), kitchen display dengan realtime Supabase, CRUD produk (varian, add-on, upload gambar), CRUD kategori (urutkan/aktif), CRUD add-on, manajemen meja + generate/unduh/regenerate QR, pengaturan (brand, service charge, pajak, wajib nama).

**Integritas data**: semua total dihitung server-side via RPC `create_order` dalam satu transaksi — validasi ketersediaan produk/varian/add-on, snapshot harga & nama di `order_items`, konstrain DB (`quantity > 0`, `price >= 0`), RLS di semua tabel (customer tidak pernah akses DB langsung; semua lewat server route dengan service role), rate limit pembuatan pesanan.

## Setup

1. **Buat project Supabase** di [supabase.com](https://supabase.com) (gratis).

2. **Jalankan SQL**: buka SQL Editor di dashboard Supabase, paste seluruh isi `supabase/migrations/0001_init.sql`, jalankan. Ini membuat skema, RLS, RPC, storage bucket, dan seed data (kategori, produk contoh, meja 1-6).

3. **Buat user admin**: dashboard Supabase → Authentication → Users → *Add user* (email + password). Lalu jalankan di SQL Editor (ganti UUID dengan ID user yang baru dibuat):

   ```sql
   insert into profiles (id, full_name, role) values ('<user-uuid>', 'Owner', 'admin');
   ```

   Role lain: `manager`, `kitchen`, `cashier`.

4. **Environment**: salin `.env.example` ke `.env` dan isi dari Supabase → Project Settings → API:

   ```
   NUXT_SUPABASE_URL=<Project URL>
   NUXT_SUPABASE_ANON_KEY=<anon public key>
   NUXT_SUPABASE_SERVICE_KEY=<service_role key>   # hanya untuk server, jangan pernah commit
   ```

5. **Jalankan**:

   ```bash
   npm install
   npm run dev
   ```

6. **Coba**: buka `/admin/login`, login, buka *Meja & QR*, unduh QR meja, scan/buka `http://localhost:3000/menu?t=<token>`, buat pesanan, pantau di `/admin/kitchen`.

## Deploy

- **Vercel**: import repo, set 3 env var di atas, deploy.
- Supabase tetap dipakai sebagai DB/Auth/Storage/Realtime.

## Catatan teknis (ponytail)

- Customer tracking pakai polling 5 detik (bukan realtime) — langganan realtime anon + RLS menambah kompleksitas tanpa manfaat nyata; pindah ke channel realtime jika perlu push.
- Rate limit in-memory per proses — cukup untuk 1 instance; pakai Redis jika multi-instance.
- Varian multi-grup disimpan sebagai kumpulan `variant_ids`; nama digabung (`Large · Less Sugar`) di snapshot order.
- Tidak ada promosi/loyalty/payment gateway di MVP (sesuai scope task).
