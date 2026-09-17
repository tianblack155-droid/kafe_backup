package commerce

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// The optional internal orderIDs predicate exercises the SAME SQL and worker,
// but only fixture rows. It is never populated by production startup. Unlike
// truncation/resetting published_at, this cannot consume another test's events.
func realtimeOutbox(t *testing.T, a *API, id string) *outboxStore {
	t.Helper()
	cfg := a.DB.Config()
	cfg.AfterConnect = func(ctx context.Context, c *pgx.Conn) error {
		_, err := c.Exec(ctx, "set role tkm_runtime")
		return err
	}
	db, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(db.Close)
	return &outboxStore{db: db, orderIDs: []string{id}}
}
func insertRealtimeEvent(t *testing.T, a *API, id string, version int) string {
	t.Helper()
	var eid string
	if err := a.DB.QueryRow(context.Background(), `insert into tkm.outbox_events(order_id,event_type,order_version) values($1,'ORDER_REVIEWED',$2) returning id`, id, version).Scan(&eid); err != nil {
		t.Fatal(err)
	}
	return eid
}
func pendingRealtimeEvents(t *testing.T, a *API, id string) int {
	t.Helper()
	var n int
	if err := a.DB.QueryRow(context.Background(), `select count(*) from tkm.outbox_events where order_id=$1 and published_at is null`, id).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}
func TestRealtimeOutboxCommitLockRetry(t *testing.T) {
	a, id, token, _ := realtimeFixture(t)
	store := realtimeOutbox(t, a, id)
	rt, s := realtimeServer(t, RealtimeConfig{API: a})
	c := dialRealtime(t, s)
	subscribeOrder(t, c, id, token)
	readRealtime(t, c)
	ctx := context.Background()
	tx, err := a.DB.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	var first string
	if err = tx.QueryRow(ctx, `insert into tkm.outbox_events(order_id,event_type,order_version) values($1,'ORDER_CREATED',1) returning id`, id).Scan(&first); err != nil {
		t.Fatal(err)
	}
	if n, err := store.dispatchBatch(ctx, rt, 1); err != nil || n != 0 {
		t.Fatal("uncommitted event visible", n, err)
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	second := insertRealtimeEvent(t, a, id, 2)
	lock, err := a.DB.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Rollback(ctx)
	if _, err = lock.Exec(ctx, "select id from tkm.outbox_events where id=$1 for update", first); err != nil {
		t.Fatal(err)
	}
	if n, err := store.dispatchBatch(ctx, rt, 1); err != nil || n != 1 {
		t.Fatal(n, err)
	}
	if v := readRealtime(t, c); v["event_id"] != second {
		t.Fatal("SKIP LOCKED", v)
	}
	if err = lock.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	// Force a real DB UPDATE failure, scoped solely to this fixture's event. A
	// failed transaction must preserve intent even if a local invalidation escaped.
	if _, err = a.DB.Exec(ctx, `create function tkm.ws_test_fail_publish() returns trigger language plpgsql as $$ begin raise exception 'fixture failure';end $$`); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		a.DB.Exec(ctx, `drop trigger if exists ws_test_fail_publish on tkm.outbox_events; drop function if exists tkm.ws_test_fail_publish()`)
	})
	sql := `create trigger ws_test_fail_publish before update on tkm.outbox_events for each row when (old.id='` + first + `'::uuid) execute function tkm.ws_test_fail_publish()`
	if _, err = a.DB.Exec(ctx, sql); err != nil {
		t.Fatal(err)
	}
	if _, err = store.dispatchBatch(ctx, rt, 1); err == nil {
		t.Fatal("DB failure hidden")
	}
	if n := pendingRealtimeEvents(t, a, id); n != 1 {
		t.Fatal("lost retry intent", n)
	}
	if _, err = a.DB.Exec(ctx, `drop trigger ws_test_fail_publish on tkm.outbox_events`); err != nil {
		t.Fatal(err)
	}
	if n, err := store.dispatchBatch(ctx, rt, 1); err != nil || n != 1 {
		t.Fatal(n, err)
	}
	if n := pendingRealtimeEvents(t, a, id); n != 0 {
		t.Fatal(n)
	}
	var count int
	if err = a.DB.QueryRow(ctx, `select count(*) from tkm.outbox_events where order_id=$1`, id).Scan(&count); err != nil || count != 2 {
		t.Fatal("event rows not retained", count, err)
	}
}
func TestRealtimeWorkerRestartBacklogAndClose(t *testing.T) {
	a, id, token, _ := realtimeFixture(t)
	store := realtimeOutbox(t, a, id)
	rt, s := realtimeServer(t, RealtimeConfig{API: a, PollInterval: 10 * time.Millisecond, BatchSize: 1})
	c := dialRealtime(t, s)
	subscribeOrder(t, c, id, token)
	readRealtime(t, c)
	eid := insertRealtimeEvent(t, a, id, 1)
	rt.store = store
	if err := rt.Start(context.Background(), slog.New(slog.NewTextHandler(io.Discard, nil))); err != nil {
		t.Fatal(err)
	}
	if v := readRealtime(t, c); v["event_id"] != eid {
		t.Fatal(v)
	}
	rt.Close()
	expectRealtimeClosed(t, c)
	// The marker may commit after enqueue; Close must have waited for that commit
	// or rollback before the pool is closed. Startup scans remaining backlog.
	insertRealtimeEvent(t, a, id, 2)
	restarted, s2 := realtimeServer(t, RealtimeConfig{API: a, PollInterval: 10 * time.Millisecond, BatchSize: 1})
	c2 := dialRealtime(t, s2)
	subscribeOrder(t, c2, id, token)
	readRealtime(t, c2)
	restarted.store = store
	if err := restarted.Start(context.Background(), slog.New(slog.NewTextHandler(io.Discard, nil))); err != nil {
		t.Fatal(err)
	}
	// Restart is not replay: only pending rows dispatched, ready requires REST.
	deadline := time.Now().Add(2 * time.Second)
	for pendingRealtimeEvents(t, a, id) > 0 && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	if n := pendingRealtimeEvents(t, a, id); n != 0 {
		t.Fatal("backlog not drained", n)
	}
	restarted.Close()
	expectRealtimeClosedAfterQueued(t, c2)
	if err := restarted.Start(context.Background(), nil); err == nil {
		t.Fatal("started closed worker")
	}
}
func expectRealtimeClosedAfterQueued(t *testing.T, c interface {
	Read(context.Context) (websocket.MessageType, []byte, error)
}) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	for {
		_, _, err := c.Read(ctx)
		if err != nil {
			if ctx.Err() != nil {
				t.Fatal("not closed")
			}
			return
		}
	}
}
