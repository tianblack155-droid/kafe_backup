Realtime backend (single active Go instance)
===========================================

Startup and API
---------------
REALTIME_ORIGINS is parsed by config.Load at actual cmd/server startup. Empty or
whitespace-only disables GET /api/v1/realtime and outbox consumption. Otherwise
supply comma-separated exact serialized HTTP(S) origins (no path, trailing
slash, credentials, query, fragment or wildcard). Example:

    REALTIME_ORIGINS=https://cafe.example,http://localhost:3000

Apply migrations/0004_realtime_publication.sql after 0001-0003. It adds only
UPDATE(published_at) on tkm.outbox_events to tkm_runtime. No catalog/profile
permissions are expanded. Auth remains the existing Supabase /auth/v1/user
lookup plus public.profiles id/role allowlist. No live Auth validation was
performed during implementation; integration tests use a local mock Auth.

For an in-module httptest server or runner:

    rt, err := commerce.NewRealtime(commerce.RealtimeConfig{
        API: &commerce.API{DB: pool, AuthURL: authURL, AuthKey: authKey},
        Origins: []string{"http://localhost:3000"},
    })
    // Handle err. A nil API.Client defaults to http.DefaultClient.
    defer rt.Close() // before pool.Close()
    err = rt.Start(ctx, logger) // once, only when durable dispatch is wanted
    // Handle err; mount this handler directly in app.Serve or httptest:
    handler := rt.Handler(commerce.NewHandler(pool, authURL, authKey))

NewRealtime does not start a worker. ServeHTTP itself can be used as the endpoint.
Handler mounts it outside the REST eight-second timeout. Start binds the worker
and sockets to ctx; Close is idempotent, cancels sockets and waits for handlers
and the worker. cmd/server closes realtime, then expiry, then the DB pool, even
on HTTP serve failure. http.Server.Shutdown alone cannot close hijacked sockets.

Protocol and bounds
-------------------
Origins are exact matched, including scheme and port. Absent/null/foreign Origin
and any query string (even a bare '?') fail before upgrade. Compression disabled.
The first message must be text JSON within five seconds, at most 12 KiB:

    {"type":"subscribe","channel":"cashier","access_token":"..."}
    {"type":"subscribe","channel":"order","order_id":"UUID","order_token":"..."}

Only those channel-specific credentials are accepted. Customer authority is the
existing canReadOrder exact order ID + hashed checkout capability, never table
QR. Staff expiry is extracted as an additional bound from JWT exp, not trusted
as authentication; the bearer must pass Auth and the profile check. Missing or
invalid exp fails closed. Customer capabilities have no timestamp expiry in the
existing schema: removal/replacement of checkout_keys revokes them. Order status
expiry does not revoke order read capability (customers need the expired view).

Register before {"type":"ready"}; then send only:

    {"type":"order.changed","event_id":"UUID","order_id":"UUID","version":1,"event_type":"ORDER_CREATED"}

Cashier receives all order invalidations; customer receives only its exact order.
The event_type is the existing outbox value. No full order, PII or token is sent.
One immutable subscription: additional application messages close the socket.
Policy violations and shutdown use immediate transport closure rather than a
close-handshake wait, bounding resource use. No token-bearing errors are logged.

Defaults: 100 total connections including unauthenticated sockets, five per
staff ID / customer order capability scope, 32 outgoing events per socket,
five-second auth/write/pong deadlines, 20-second heartbeat, 30-second staff and
customer revalidation, exact JWT expiry deadline. Positive RealtimeConfig bounds
can tighten but not relax defaults. Queue overflow disconnects the slow reader;
there is no unbounded fanout goroutine or silent event drop on a live socket.

Durability and recovery
----------------------
A 250ms worker polls up to 100 committed pending outbox rows. In one transaction:
SELECT FOR UPDATE SKIP LOCKED, enqueue scoped invalidation, UPDATE published_at,
COMMIT. Rows are retained. Database errors roll back publication; retry can send
a duplicate. Publication means LOCAL hub dispatch, not browser acknowledgement.
No subscribers is still a completed local dispatch. Shutdown may cancel a batch,
leaving intent pending. The worker never publishes uncommitted commerce changes.

There is no replay/cursor guarantee and no multi-instance distribution support.
A crash after publication may miss browser delivery; failure before commit can
duplicate it. Clients must refetch authoritative REST on ready/event/reconnect,
retain periodic reconciliation and fall back to REST when disconnected.

Tests and isolation
-------------------
Use a disposable DB clone with migrations 1-4, never production:

    export PATH=/root/.local/toolchains/go1.27.1/go/bin:$PATH
    export TEST_DATABASE_URL='postgres:///teraskayumanis_ws_test?host=/var/run/postgresql'
    go test -race ./...
    go vet ./...
    psql "$TEST_DATABASE_URL" -X -f tests/realtime.sql

Socket-only tests do not start an outbox worker. Dispatcher/worker tests use an
unexported orderIDs predicate, nil in production, restricting the same production
query to generated fixture order IDs. Cleanup deletes only fixture rows; no
TRUNCATE, global marker reset, or permanent consumption of other tests' events.
The failure-injection trigger is restricted to a fixture event ID and removed
on cleanup. SQL tests are transactional and roll back their fixtures.

Coverage includes exact origins/query rejection, capability scoping/table-QR
rejection, mock Auth/profile revocation, customer revocation, JWT expiry,
auth deadline/frame size/type, extra frames, global/identity bounds, overflow,
heartbeat, >8s REST and >10s real app lifetime, shutdown, transactional visibility,
SKIP LOCKED, UPDATE failure/retry, row preservation, restart/backlog, narrow
runtime grants, and checkout/review/payment/completion/expiry invalidations with
an authoritative REST snapshot. RED/GREEN execution transcript is saved at
/tmp/tkm-ws-backend-evidence.txt (local implementation artifact, not committed).
