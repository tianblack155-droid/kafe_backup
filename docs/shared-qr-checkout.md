# Shared QR ordering — no table identity

User-corrected contract: one QR opens `https://teraskayumanis.alrizky.id/menu`.
Phone camera -> website -> menu -> cart -> submit. No in-app scanner, table query,
table cookie, table selection, or dummy/default table is required. Orders use
order number and customer name. Existing cash review/paid/completed and expiry
rules are unchanged. Removing table identity does NOT remove the private
order capability used for REST tracking and WebSocket subscriptions.

## Change

- Customer menu/cart do not resolve a table or gate checkout on `table_token`.
  Active cashier/tracking screens do not show a table identity.
- Migration `0005_shared_qr_checkout.sql` makes `orders.table_id` nullable;
  all new checkout rows use NULL. No historical data or old table references
  are deleted. `order_json` uses a left join and returns `tables: null` for new orders.
- Review pricing stages a tableless order. Reorder works for both new and historical
  expired orders and returns a new payload without `table_token`.
- Existing pending checkout attempts retain their exact body/key/capability.
  Backend still accepts/serializes the legacy field identically for retry equality,
  but never uses it for a new table assignment. Do not add `omitempty` or normalize
  stored payloads during this migration: that would break uncertain old retries.
- Functions remain invoker, empty search_path, same privileges. No runtime admin grants.

## Public deployment verified

- Application `76b0976` deployed to New Jersey; migration5 applied and read back.
- Actual Chromium on public domain, fresh anonymous customer context: `/menu` ->
  Tambah -> Keranjang -> Pesan Sekarang returned201 without table cookie or field.
  Database readback confirmed `table_id IS NULL`; no dummy/table row assigned.
- Separate real Supabase temporary cashier saw the order via WSS, reviewed, confirmed
  paid and completed. Customer tracking reload, idempotent replay and wrong-order
  capability denial passed; no browser page errors.
- Exact temporary order/payment/outbox/key and Auth user/profile cleaned and absence
  verified. User-owned cashier account and existing orders untouched.
- 29 frontend tests,17 renderer tests, Go race/vet/build, Node/Vercel builds, fresh
  PostgreSQL16 migrations/ACL/historical retry tests and both local browser suites passed.
- Independent source review passed with no blocking findings.

## Verification

- Red reproduced both real cart component refusing to submit without a cookie and
  runtime SQL failing with `Invalid table`. Green tests exercise the new contract.
- `npm run test:structure`: component checkout + page contract + existing regressions.
- `backend/tests/shared_qr_migration.sql`: run at migration4, creates a real historical
  checkout, applies5 inside a transaction, compares old snapshot/identity/grants,
  verifies name validation/review/auth then rolls back. CI runs it before applying5.
- Go shared-QR runtime HTTP tests cover absent/empty/invalid/old table fields, NULL
  table association, capability auth, exact retries/conflicts, payment review gate,
  cash completion, expiry and reorder. Migrations1–4 remain untouched.
- `scripts/browser-realtime.mjs` now actually opens bare `/menu` in a clean browser,
  clicks Tambah -> Keranjang -> Pesan Sekarang, asserts no table cookie/payload and
  NULL DB table, then verifies cashier/customer WSS, review/payment/completion,
  restart/reconnect and isolation. Local Auth is explicitly mocked.
- `scripts/browser-order-flow.mjs` verifies quantity revision, completion/history,
  customer and cashier reorder. Both suites clean exact test-product orders, not
  by table_id, and target the intended order card.

Run browser scripts with `BROWSER_TEST_DB=teraskayumanis_no_table`, migrations1–5,
current `backend/bin/server`, Node Nuxt output, Playwright and Caddy paths as in
`realtime-websocket.md`. Do not mistake direct API checkout for customer UI proof.

Legacy table admin/API files are retained migration debt and are not active checkout
requirements. QR image generation/printing and physical camera scanning are separate
artifacts; a successful URL/browser test does not claim those were performed.
