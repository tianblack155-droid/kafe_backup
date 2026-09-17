# WebSocket realtime — preview contract

This extends cash-only ordering, not a new business-state machine. Cashier reviews
availability/total **before** accepting cash, then confirms paid; completion remains
separate after all items are delivered. No kitchen/KDS or Flutter/FCM implementation.

## Transport and scope

- Public `wss://teraskayumanis.alrizky.id/ws` is routed directly by Caddy to
  Go `GET /api/v1/realtime`; it bypasses Nitro's ordinary HTTP BFF.
- Configure `REALTIME_ORIGINS` to an explicit comma-separated list of complete
  HTTP(S) origins. No origins means WebSocket disabled. No missing/null/foreign
  origins; no wildcard. Production deployment renderer fixes the preview origin.
- Tokens are **not** in URLs, cookies, or logs for this transport. Client sends
  one bounded JSON subscription frame after upgrade, within five seconds:

```json
{"type":"subscribe","channel":"cashier","access_token":"<Supabase access token>"}
```

```json
{"type":"subscribe","channel":"order","order_id":"<UUID>","order_token":"<checkout capability>"}
```

Staff must pass Supabase `/auth/v1/user` plus the existing allowed `profiles` role.
Customer capability is checked against that exact order's hashed checkout token;
QR table tokens are not order ownership. Only one immutable subscription is allowed.
No order mutations are accepted through WebSocket; REST remains the write API.

The server registers a scoped peer and sends `{"type":"ready"}`. That triggers a
fresh REST snapshot. Subsequent notifications contain only:

```json
{"type":"order.changed","event_id":"<UUID>","order_id":"<UUID>","version":2,"event_type":"ORDER_REVIEWED"}
```

Cashier peers receive order invalidations; a customer peer only receives its exact
order. No order details, customer names, money, capabilities or tokens are broadcast.

## Recovery and delivery limits

- Existing business transactions already create durable `tkm.outbox_events`.
  A single Go dispatcher locks committed pending rows (`FOR UPDATE SKIP LOCKED`),
  enqueues minimal invalidations, marks `published_at`, then commits. Event rows stay.
- Migration `0004_realtime_publication.sql` adds only `UPDATE(published_at)` to
  `tkm_runtime`. It does not grant catalog/profile editing or broad event UPDATE.
- `published_at` means local dispatch, **not** browser receipt or staff acceptance.
  Failures can duplicate invalidations or interrupt delivery. There is no event replay
  cursor or exactly-once promise. A UUID is not an ordering/replay cursor.
- Clients refetch authoritative REST on ready, event, reconnect and foreground return.
  Duplicate notification memory is bounded. Bursts coalesce; a change during a fetch
  gets a trailing refresh. Old requests are aborted/ignored when scope changes.
- While connected, REST reconciliation remains periodic. Disconnected clients fall
  back to polling and retry with bounded exponential backoff/jitter and fresh auth.
  Cashier drafts/editor/input money are not replaced by background invalidations.
- This design is for **one active Go instance**. Multiple independent dispatchers
  would split notifications between local hubs; horizontal scaling needs fan-out.

## Connection limits and lifecycle

Global connection cap, per-identity cap, bounded outgoing queues, max 12 KiB first
frame, auth deadline, ping/pong and write deadlines constrain resources. Slow peers
are disconnected and must resync. Compression is disabled. Revalidation periodically
checks staff authority/customer capability; JWT expiry also caps staff connection.
Logout closes local socket; role revocation is detected by periodic revalidation,
not an instantaneous cross-device session revocation guarantee.

Socket lifetime is not the REST handler's eight-second context. Main owns dispatcher,
expiry worker and sockets, shutting these down before pool close. Ordinary net/http
Shutdown alone does not close hijacked sockets.

## Verification commands

```sh
npm run test:structure
npm run typecheck
python3 -m unittest deploy.test_render_env
TEST_DATABASE_URL='<disposable local Postgres with migrations 1-4>' go -C backend test -race ./...
go -C backend vet ./...
go -C backend build -o bin/server ./cmd/server
npm run build
PLAYWRIGHT_MODULE='<playwright module>' CADDY_BIN='<caddy>' \
  BROWSER_TEST_DB=teraskayumanis_ws_browser node scripts/browser-realtime.mjs
```

The browser runner uses actual local Go/Postgres/Nuxt/Caddy/WebSocket and **mock Auth**,
not a user's Supabase password. Live deployment checks must be recorded separately.
Test against disposable databases; fixture triggers in outbox failure tests must not
be run on production. The old runtime role bootstrap test precedes migration4 in CI.

## Verified deployment — 2026-09-17

- Code reviewed independently with no blocking findings; application revision `b5ef30d`
  deployed to New Jersey. Caddy /ws -> Go upgrade is active, services non-root and ready.
- Migration4 applied/read back on Supabase: publication-column UPDATE true, broad UPDATE
  and payload-column UPDATE false; runtime rollback grant test passed on cloud.
- 27 frontend tests, 17 renderer tests, typecheck, Go race/vet/build, Node/Vercel builds,
  fresh PostgreSQL16 cluster migration1–4 + full role guard/lifecycle/realtime SQL passed.
- Local Chromium actual Caddy/Go/Postgres/Nuxt: checkout/review/payment/completion events,
  customer isolation, server restart/reconnect and logout passed (mock Auth disclosed).
- Public WSS probe: authorized customer ready, expiry outbox invalidation, cross-order
  isolation, wrong capability, foreign origin, credential query and invalid staff denial.
- Public Chromium **real Supabase Auth** using an isolated temporary cashier: password
  login, cashier order.created invalidation, customer paid/completed invalidations,
  transport-close/reconnect and logout all passed; no page exceptions.
- The public probe measured one order arrival at 595ms from the Hermes host, not Indonesia
  and not a latency guarantee. No load-test or multi-instance claim.
- Chromium offline emulation blocked fetch but left established WS open (readyState1,
  no close event); the fault test explicitly closed the real native socket before
  restoring network. It did not mock server events or fabricate reconnection.
- Temporary Auth user/profile/table/payments/orders were removed and absence verified;
  original cashier remains untouched. Sample menu/meja1 remain. Sequence gaps are normal.
- User-owned cashier password was never supplied to the agent; user should test their
  own session. Production operations/admin CRUD/report/backup-restore/monitoring and
  multi-instance fan-out remain separate work; PR is still draft, main unchanged.

## Sample catalog (historical table-aware setup)

**Superseded by shared QR:** use plain `/menu`, no table identity/query. The sample
product remains; prior Meja1 test link is not required or the current product flow.
See [shared QR checkout](shared-qr-checkout.md).

One user-requested sample is present in preview: **Es Teh Manis (Uji), Rp5.000**,
category Menu Uji, Meja 1. It is not the final cafe catalog. Test transactions affect
order history; do not reset sequences or delete user orders to hide testing activity.

## References read for this implementation

- [Coder WebSocket](https://github.com/coder/websocket): context-aware connection,
  ping/pong, close and origin handling.
- [OWASP WebSocket Security](https://cheatsheetseries.owasp.org/cheatsheets/WebSocket_Security_Cheat_Sheet.html):
  origin allowlist, message auth, expiry, payload bounds and log secrecy.
- [Caddy reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy):
  WebSocket upgrade support and long-lived connection proxying.
