package commerce

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/jackc/pgx/v5/pgxpool"
	"io"
	"log/slog"
	"os"
	"sync"
	"testing"
	"time"
)

func TestConcurrentReviewPaymentExpiry(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL required")
	}
	ctx := context.Background()
	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	tx, err := db.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	var actor, cat, prod, table string
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	must(tx.QueryRow(ctx, "insert into public.profiles(id,role) values(gen_random_uuid(),'cashier') returning id").Scan(&actor))
	must(tx.QueryRow(ctx, "insert into public.categories(name,slug) values('CONCURRENT',gen_random_uuid()::text) returning id").Scan(&cat))
	must(tx.QueryRow(ctx, "insert into public.products(category_id,name,slug,price) values($1,'CONCURRENT',gen_random_uuid()::text,10000) returning id", cat).Scan(&prod))
	must(tx.QueryRow(ctx, "insert into public.tables(number) values(99996) returning qr_token").Scan(&table))
	must(tx.Commit(ctx))
	var ids []string
	defer func() {
		for _, id := range ids {
			db.Exec(ctx, "delete from tkm.checkout_keys where order_id=$1", id)
			db.Exec(ctx, "delete from tkm.outbox_events where order_id=$1", id)
			db.Exec(ctx, "delete from public.payments where order_id=$1", id)
			db.Exec(ctx, "delete from public.orders where id=$1", id)
		}
		db.Exec(ctx, "delete from public.tables where qr_token=$1", table)
		db.Exec(ctx, "delete from public.products where id=$1", prod)
		db.Exec(ctx, "delete from public.categories where id=$1", cat)
		db.Exec(ctx, "delete from public.profiles where id=$1", actor)
	}()
	items := fmt.Sprintf(`[{"product_id":%q,"quantity":1,"variant_ids":[],"addon_ids":[]}]`, prod)
	payload := fmt.Sprintf(`{"table_token":%q,"payment_method":"cash","items":%s}`, table, items)
	create := func(suffix string) string {
		var id string
		must(db.QueryRow(ctx, "select tkm.checkout($1,$2,$3::jsonb)->>'id'", actor+suffix, actor+actor, payload).Scan(&id))
		ids = append(ids, id)
		return id
	}
	id := create("one")
	// Two cashiers reading the same version: only one revision can win.
	var wg sync.WaitGroup
	results := make(chan error, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, e := db.Exec(ctx, "select tkm.review_order($1,$2,1,$3::jsonb)", id, actor, items)
			results <- e
		}()
	}
	wg.Wait()
	close(results)
	failures := 0
	for e := range results {
		if e != nil {
			failures++
		}
	}
	if failures != 1 {
		t.Fatalf("review stale failures %d", failures)
	}
	results = make(chan error, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, e := db.Exec(ctx, "select tkm.confirm_cash($1,$2,10000,2)", id, actor)
			results <- e
		}()
	}
	wg.Wait()
	close(results)
	for e := range results {
		must(e)
	}
	var count int
	must(db.QueryRow(ctx, "select count(*) from public.payments where order_id=$1", id).Scan(&count))
	if count != 1 {
		t.Fatal("duplicate payment", count)
	}
	// Payment waits behind another transaction until deadline has passed.
	late := create("late")
	_, err = db.Exec(ctx, "select tkm.review_order($1,$2,1,$3::jsonb)", late, actor, items)
	must(err)
	lock, err := db.Begin(ctx)
	must(err)
	_, err = lock.Exec(ctx, "update public.orders set created_at=clock_timestamp()-interval '15 minutes'+interval '100 milliseconds' where id=$1", late)
	must(err)
	answer := make(chan []byte, 1)
	errCh := make(chan error, 1)
	go func() {
		var out []byte
		e := db.QueryRow(ctx, "select tkm.confirm_cash($1,$2,10000,2)", late, actor).Scan(&out)
		answer <- out
		errCh <- e
	}()
	time.Sleep(150 * time.Millisecond)
	must(lock.Commit(ctx))
	out := <-answer
	must(<-errCh)
	var result map[string]any
	must(json.Unmarshal(out, &result))
	if result["error"] != "expired" {
		t.Fatalf("paid after waiting beyond expiry: %s", out)
	}
	// Background worker persists expiry without an HTTP request and stops cleanly.
	sweep := create("sweep")
	_, err = db.Exec(ctx, "update public.orders set created_at=clock_timestamp()-interval '16 minutes' where id=$1", sweep)
	must(err)
	workerCtx, cancel := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() { RunExpiry(workerCtx, db, slog.New(slog.NewTextHandler(io.Discard, nil))); close(done) }()
	deadline := time.After(2 * time.Second)
	for {
		var status string
		must(db.QueryRow(ctx, "select status from public.orders where id=$1", sweep).Scan(&status))
		if status == "expired" {
			break
		}
		select {
		case <-deadline:
			cancel()
			t.Fatal("sweep failed")
		default:
			time.Sleep(10 * time.Millisecond)
		}
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("worker shutdown")
	}
}
