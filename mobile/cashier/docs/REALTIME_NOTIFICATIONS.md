# Realtime dan notifikasi kasir

## WebSocket yang sudah tersedia

Flutter memakai **Go WebSocket**, bukan Supabase Realtime channel. Endpoint preview
`wss://teraskayumanis.alrizky.id/ws`, origin yang diizinkan
`https://teraskayumanis.alrizky.id`.

Pada native Dart, `WebSocket.connect` **harus mengirim header Origin secara eksplisit**.
Backend menolak missing/foreign Origin dengan403. Jangan menonaktifkan origin validation
di Go agar client lolos. Native Origin bukan rahasia/bukti autentikasi; staff JWT tetap
wajib diverifikasi server. URL tidak boleh mengandung token/query credential.

Setelah socket open, kirim **satu text frame** maksimal12KiB dalam5detik:

```json
{"type":"subscribe","channel":"cashier","access_token":"<Supabase access token>"}
```

Tunggu server `{"type":"ready"}` sebelum status “Realtime tersambung”. Open TCP/upgrade
saja bukan subscription berhasil. Ready harus memicu REST snapshot, bukan menunggu event
pertama. Tidak ada frame auth-refresh atau resubscribe pada socket sama; tutup dan buka
socket baru dengan token terkini ketika refresh/resume/retry.

Event notifikasi (nilai contoh):

```json
{"type":"order.changed","event_id":"<UUID>","order_id":"<UUID>","version":3,"event_type":"ORDER_PAYMENT_CONFIRMED"}
```

Jenis event sekarang: ORDER_CREATED, ORDER_REVIEWED, ORDER_PAYMENT_CONFIRMED,
ORDER_COMPLETED, ORDER_EXPIRED. Toleransi event bisnis baru sebagai invalidation;
jangan crash ketika enum server bertambah. Tidak ada detail/nama/uang/token di frame.
Fetch ulang REST untuk data. Server tidak menerima mutasi lewat socket.

## Pemulihan

- Dedup event_id dengan memori bounded; jangan menganggap UUID urutan waktu.
- Burst event -> satu refresh + trailing refresh jika datang saat fetch berlangsung.
- Jangan membiarkan response lama menimpa version yang lebih baru atau tab/akun baru.
- Ready/reconnect/resume -> snapshot. Periodic reconciliation tetap diperlukan bahkan
  socket connected, karena published_at bukan ACK dari client.
- Fallback polling ketika disconnected; retry exponential backoff+jitter berbatas.
- Auth token expired/role revoked bisa memutus socket; ambil token terbaru. Jangan
  melonggarkan auth atau menyimpan token lama secara permanen di service constructor.
- Backend ping/pong20detik, timeout write/auth5detik, revalidation30detik.
- Backend saat ini maksimal100socket global,5per identity, queue32. Hindari membuat
  socket baru untuk setiap widget/order dan tidak menutup yang lama.
- Current outbox/single Go instance: local publish marker bukan delivery receipt atau
  jaminan exactly-once. Horizontal scaling harus shared fanout, bukan dua hub terpisah.

## Foreground UX sekarang

Order baru yang terdeteksi ketika app aktif dapat memberi snackbar/indikator dan bunyi
sistem. Jangan membunyikan semua order lama saat login/ambil snapshot. Hindari bunyi
berulang untuk duplicate event. Operator tetap wajib melihat nomor/nama dan melakukan
review, tidak ada auto-accept/auto-payment. Suara boleh tidak terdengar jika device silent;
UI visual harus tetap jelas.

Lifecycle Flutter:
- resumed -> fresh token, reconnect, resync snapshot.
- paused/hidden/detached -> hentikan stream aktif/poll timer, tidak janji socket bertahan.
- signed out -> tutup socket, bersihkan data layar dan subscriptions.
- token refreshed -> reconnect dengan token baru, guard terhadap respons sesi sebelumnya.

**WebSocket bukan push notification.** App tertutup, di-kill, OS suspend atau battery
optimizer dapat menghentikan socket. Jangan menjanjikan order selalu berbunyi dalam
kondisi itu. Starter belum punya Firebase project/config, token registration endpoint,
FCM dispatcher atau permission push.

## Roadmap FCM (belum diimplementasikan)

Implementasi harus koordinasi backend + mobile; jangan membuat endpoint fiktif di client.

1. Pemilik menyiapkan Firebase project/applicationId yang disepakati, serta APNs jika iOS.
   Android `google-services.json` bukan service account; kredensial admin FCM hanya server.
2. Sepakati endpoint registration **baru** untuk device staff, misalnya proposal
   `POST /api/v1/staff/devices` (belum ada). Request ber-Bearer; backend mengikat
   device/token pada staff user terverifikasi. Device ID acak, bukan hardware fingerprint.
3. Desain upsert/token rotation, unregister/logout, multi-device, role revocation,
   token invalid cleanup, TTL. Jangan menerima user_id bebas dari client sebagai owner.
4. Dispatcher durable FCM dengan retry/backoff/idempotent event ID. **Jangan menggunakan
   published_at WebSocket sebagai satu-satunya status push**: delivery channel terpisah
   butuh marker/attempt records terpisah, agar event tidak hilang atau dianggap sent dua kali.
5. Payload minimal event_id/order_id/type; hindari nama/uang di lock screen secara default.
   Push bukan authority; login + REST fetch ulang setelah tap.
6. Android notification channel dan runtime POST_NOTIFICATIONS permission sesuai OS;
   iOS permission/APNs/capabilities. Permission ditolak harus tetap bisa pakai app.
7. Foreground vs background vs terminated handlers, initial-message/deep-link ke order,
   duplicate suppression antara WSS dan FCM. App sudah login user yang benar sebelum detail.
8. Test device nyata: battery saver, Android vendor restrictions, token refresh,
   signout/login user lain, permission revoked, airplane mode, reboot, duplicate events.

FCM bukan jaminan tepat waktu/exactly-once. Tetap resync dari backend. Hindari meminta
battery exemption/foreground service tanpa kebutuhan operasional dan persetujuan.

## Sumber

- [Flutter lifecycle](https://api.flutter.dev/flutter/widgets/WidgetsBindingObserver/didChangeAppLifecycleState.html)
- [Dart WebSocket.connect](https://api.dart.dev/dart-io/WebSocket/connect.html)
- [Firebase Flutter messaging](https://firebase.google.com/docs/cloud-messaging/flutter/client)
- [Backend realtime contract](../../../docs/realtime-websocket.md).

Roadmap di atas proposal pengembangan, bukan klaim endpoint/push sudah live.
