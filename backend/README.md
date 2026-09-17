# Backend Go — foundation

> Update: flow cash-only Go sedang diimplementasikan. Lihat [cash-only-status](../docs/cash-only-status.md) untuk status terbaru; bagian fondasi di bawah bersifat historis. Migration dan runtime Go/Nuxt sudah terhubung ke Supabase; [Auth E2E/deployment masih tersisa](../docs/runtime-supabase-2026-09-17.md). Belum siap production.

Dokumen target: [arsitektur.md](arsitektur.md). Implementasi saat ini **bukan seluruh arsitektur**.

## Sudah berjalan

- `cmd/server`: HTTP server Go, JSON logging (`slog`), SIGINT/SIGTERM graceful shutdown.
- `internal/config`: validasi environment, host/port, dan PostgreSQL URL.
- `internal/httpapi`: `GET /health` dan `GET /ready`.
- `internal/app`: HTTP timeouts dan shutdown maksimum 10 detik.
- `pgxpool`: maksimal 5 koneksi, connect timeout 2 detik; readiness ping deadline 2 detik.
- Unit test, HTTP test, race detector, vet, binary build.

`/health` = proses HTTP hidup, bukan bisnis aplikasi sehat.
`/ready` = PostgreSQL dapat di-ping; belum memeriksa schema, auth, outbox atau FCM.
Tanpa DATABASE_URL atau DB tidak terjangkau, `/ready` mengembalikan **503**, bukan sukses palsu.

## Jalankan

Prasyarat Go 1.27.x (CI memakai versi dari go.mod).

```bash
cd backend
cp .env.example .env
# Edit .env sesuai kebutuhan. Jangan commit credential.
set -a
. ./.env
set +a
go mod download
go run ./cmd/server
```

`.env` harus berupa assignment shell valid; quote URL yang mengandung karakter shell.
Binary membaca environment proses, tidak otomatis mencari .env. Windows: set environment
melalui PowerShell atau IDE, jangan menjalankan perintah POSIX di atas.

```bash
curl -i http://127.0.0.1:8080/health
curl -i http://127.0.0.1:8080/ready
go test -race ./...
go vet ./...
go build -o bin/server ./cmd/server
```

APP_ENV: `development` (default), `test`, atau `production`.
Production mewajibkan DATABASE_URL. Pool dibuat lazy: URL valid tetapi DB offline tetap
menghidupkan HTTP dengan readiness 503 supaya orchestrator dapat memantau recovery.
HOST default loopback; container memakai HOST=0.0.0.0. Terminasi TLS dilakukan proxy.
Raw connection string/error database tidak dikirim ke client atau log.

## Docker (opsional)

```bash
docker build -t teraskayumanis-backend ./backend   # dari root repo
docker run --rm -p 127.0.0.1:8080:8080 --env-file backend/.env teraskayumanis-backend
```

Jika .env berisi HOST=127.0.0.1, override dengan `-e HOST=0.0.0.0` setelah --env-file.
APP_ENV=production membutuhkan database yang reachable dari container.
Dockerfile tersedia; image perlu dibangun pada mesin dengan Docker. Jangan menyalin .env ke image.

## Batas pekerjaan ini

Belum ada auth Go, order/payment API Go, migration runner Go, WebSocket, outbox worker,
FCM, Flutter atau migrasi database production. Tidak ada endpoint bisnis palsu.
CORS lintas origin belum diaktifkan: belum ada browser business API Go. Tambahkan allowlist
dan test bersama integrasi auth/API, bukan wildcard sementara.

`legacy-nuxt/` menyimpan API TypeScript lama, tetap dijalankan oleh Nitro melalui
`frontend/nuxt.config.ts`. Ini pemisahan source, **belum pemisahan runtime API bisnis**.
`supabase/migrations/0001_init.sql` adalah schema lama, termasuk role kitchen; jangan menjalankannya
sebagai schema target Go atau terhadap database berisi data tanpa review migrasi.

Target baru kasir-only. Cleanup kitchen lama, state PENDING_PAYMENT, atomic payment
confirmation, idempotency dan outbox akan dilakukan pada migrasi bisnis terpisah.
