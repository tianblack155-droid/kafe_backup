# TerasKayuManis — Monorepo

> **Kontrak QR terbaru:** satu QR bersama membuka `/menu`, tanpa identitas meja.
> Checkout/reorder tidak membutuhkan `table_token`; lihat [shared-qr-checkout](docs/shared-qr-checkout.md).

> Preview HTTPS tersedia: [customer](https://teraskayumanis.alrizky.id/menu) · [kasir](https://teraskayumanis.alrizky.id/cashier). Deployment New Jersey memakai build branch `76b0976`; belum production-approved. Lihat [deployment](deploy/README.md).

> Cash-only, review/expiry/reorder dan WebSocket kasir/pelanggan sudah diimplementasikan. Uji browser HTTPS/WSS dengan Supabase Auth asli memakai akun sementara lulus. [Realtime dan bukti terbaru](docs/realtime-websocket.md). Katalog berisi satu menu uji; belum production-approved.

Customer web, admin web, backend Go, dan calon aplikasi Flutter kasir dalam satu repo.
**Target produk:** pelanggan order di web → pending → bayar di kasir → kasir konfirmasi →
pesanan diproses dan diantar ke meja. Tidak ada kitchen/KDS dalam target baru.

> Migrasi masih bertahap: core commerce dan WebSocket sudah memakai Go; admin CRUD/report masih legacy dan diblokir pada preview. Flutter/FCM belum dibuat.

## Struktur

```text
frontend/                  Nuxt 4: app, public, shared types, config
backend/
  arsitektur.md            Dokumen arsitektur revisi (target)
  cmd/server/             Entrypoint Go
  internal/               Config, HTTP health/readiness, server lifecycle
  legacy-nuxt/            Source API Nitro lama (transisi)
  supabase/migrations/    SQL legacy, bukan schema Go baru
mobile/cashier/            Tempat Flutter kasir; README, belum aplikasi
scripts/                   Pemeriksaan struktur dan smoke test
 docs/legacy-task.md        Spesifikasi lama, bukan scope baru
```

[Arsitektur lengkap](backend/arsitektur.md) · [Backend setup](backend/README.md)
· [Frontend/legacy setup](frontend/README.md) · [Status migrasi](docs/migration.md)

## Mengapa monorepo?

Kontrak API dan perubahan web/Go/Flutter dapat direview dalam satu PR. Build dan deploy
masing-masing tetap terpisah; satu repo tidak berarti satu deployment. Untuk tim kecil,
belum perlu Nx, Turborepo, microservices atau repo Flutter terpisah. Pertimbangkan split
repo ketika ownership tim, izin akses atau siklus rilis benar-benar berbeda.

## Web

Node >=22 dan npm dengan workspaces. Satu lockfile JavaScript di root.

```bash
npm ci
cp frontend/.env.example frontend/.env
# Isi Supabase milik project; jangan commit .env.
npm run dev
```

```bash
npm run typecheck
npm run build
npm run test:structure
```

Nuxt biasanya berjalan di http://localhost:3000. API lama `/api/*` tetap dilayani
Nitro. File backend legacy berada di luar frontend melalui `serverDir`.
Tidak ada redirect otomatis semua `/api` ke Go karena Go belum punya API bisnis.

## Go

```bash
cd backend
cp .env.example .env
# Isi DATABASE_URL untuk readiness; hanya shell-safe assignments.
set -a; . ./.env; set +a
go run ./cmd/server
```

`GET /health` hidup; `/ready` 503 sampai database dapat di-ping. Detail di backend README.

## Test runtime

```bash
npm run build
cd backend && go build -o bin/server ./cmd/server && cd ..
python3 scripts/smoke.py
```

Smoke test membuka port loopback acak, menjalankan binary Go dan output produksi Nuxt,
menguji health/readiness serta API legacy, lalu menghentikan proses yang dibuatnya.
Tidak menggunakan Supabase key atau mengubah data production.

## Deployment setelah perpindahan folder

- Root install: `npm ci`; root build: `npm run build`.
- Output Node Nuxt: `frontend/.output/server/index.mjs`.
- Bila provider memakai root directory `frontend`, seluruh checkout harus tetap tersedia,
  termasuk `backend/legacy-nuxt` di luar root itu. Workspace lockfile ada di root repo.
- Vercel: gunakan **Root Directory `.`** dan konfigurasi root `vercel.json`; script
  `npm run build:vercel` menghasilkan `.vercel/output`. Panduan lengkap dan blocker
  transaksi ada di [merge-readiness](docs/merge-readiness.md). Provider belum dideploy.
- Go di-deploy terpisah dengan TLS/proxy, env dan health checks. Dockerfile opsional tersedia.
- Flutter belum digenerate; folder saat ini hanya menyediakan tempat dan batas scope.

Akun/credential, database production, visibilitas repo dan deployment tidak diubah.
