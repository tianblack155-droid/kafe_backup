# Supabase verification — 2026-09-17

Project: `aiptdjypuccoakyfvdyl` (TerasKayuManis). Source branch at verification:
`refactor/monorepo-go-foundation`, commit `7553298d2998d85bda74e3ff1eb617182e192b9b`.

## Applied and read back

The target public/tkm schemas were empty before installation. The reviewed repository
migrations were applied with Supabase MCP `apply_migration`, in order, without edits:

- `20260917022053` — `teraskayumanis_cash_only` (`backend/migrations/0001_cash_only.sql`).
- `20260917022120` — `teraskayumanis_order_review_expiry` (`backend/migrations/0002_order_review_expiry.sql`).

Readback confirmed 13 public tables and 3 internal tkm tables. The only persistent
application row is the default TerasKayuManis settings row; no real menu, table, staff,
customer, order or payment data was seeded.

## Verified on actual Supabase PostgreSQL 17.6

Tests were run as privileged management SQL through MCP, not through Go HTTP/Auth:

- `cash_lifecycle.sql`: initial pending/unpaid, server total, checkout replay, unpaid
  completion rejection, mandatory review, insufficient cash rejection, paid transition,
  change, payment replay, completion, history/outbox counts.
- `order_flow.sql`: expiry timestamp, review-required payment, unavailable menu rejection,
  unchanged version after failed review, stale review/payment rejection, review preserving
  the original deadline, paid order surviving expiry sweep, expired status/history/outbox,
  rejection of expired payment without inserting a payment.
- Additional rollback-only reorder test: an expired old order remains unchanged at the
  old price; checkout with a fresh identity uses the new catalogue price and fresh timer.

Each suite returned an explicit `passed: true`. Tests were rolled back. Exact SQL
counts afterward were zero for all 15 tables other than `public.settings` (one row).
PostgreSQL sequence increments do not roll back: test order numbers consumed sequence
values. No sequence reset was attempted; gaps are valid and do not imply lost orders.

## Access-control checks

- All 13 public tables have RLS enabled with no client policies, denying client row access.
- All 7 tkm functions are SECURITY INVOKER, with an explicitly empty search_path.
- `anon` and `authenticated` have no schema USAGE and no SELECT/INSERT/UPDATE/DELETE
  privileges on any of the 3 private tkm tables; checkout EXECUTE is also denied.
- `list_tables` emits a generic RLS-disabled warning for tkm tables. RLS is indeed disabled
  there, but its claim that anonymous clients can access them is contradicted by the
  direct ACL readback above. Do not expose/grant this schema to client roles.
- `get_advisors(type=security)` returned only INFO-level `rls_enabled_no_policy` findings
  for the 13 public tables. This is expected for the current deny-by-default schema.

These checks are not a full security certification. The restricted runtime role is
still unprovisioned. It needs explicit least-privilege grants/policies and verification;
production must not use the management/owner role just because these tests passed.

## Runtime/deployment still blocked

- No runtime `DATABASE_URL` or app `.env` exists in the checked-out monorepo.
- The direct project database endpoint resolves to IPv6; TCP from the Hermes VPS failed
  with `Network is unreachable`. This is a result for the Hermes host only, not the user's
  new New Jersey VPS, whose OS/network/SSH details have not been supplied.
- Supabase documents direct connections for persistent IPv6 backends, and the shared
  Session pooler for IPv4-only persistent backends. Copy its actual host from Dashboard
  Connect; it cannot be safely derived from a region name.[1]
- Need actual connection endpoint, dedicated runtime role/credential, app Auth configuration,
  and an explicitly designated test staff account before browser -> Go -> live Supabase E2E.
- No deployment, main merge, real staff account, or real catalogue setup was performed.

Do not rerun bootstrap migrations on this populated schema. For local disposable DBs,
repository files still apply as 0001 then 0002. Future cloud changes need new migrations.

Evidence artifacts are held outside git on the Hermes host under
`/root/.hermes/output/tkm-supabase-verification/` (migration readbacks, test sentinels,
exact counts and ACL/advisor readbacks). No secrets are included in this report.

## Sources

[1] https://supabase.com/docs/guides/database/connecting-to-postgres — Supabase Docs — Connect to your database
