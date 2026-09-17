package commerce

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/zDarkx1/TerasKayuManis/backend/internal/app"
)

func TestRealtimeRealAppLifetimeShutdown(t *testing.T) {
	a, id, token, _ := realtimeFixture(t)
	rt, err := NewRealtime(RealtimeConfig{API: a, Origins: []string{localOrigin}, PingInterval: 30 * time.Millisecond})
	if err != nil {
		t.Fatal(err)
	}
	defer rt.Close()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() {
		defer rt.Close()
		done <- app.Serve(ctx, listener, a.DB, slog.New(slog.NewTextHandler(io.Discard, nil)), rt.Handler(NewHandler(a.DB, "")))
	}()
	// Exercise the real app's 10s HTTP read/write timeouts and the REST wrapper.
	s := &httptest.Server{URL: "http://" + listener.Addr().String()}
	c := dialRealtime(t, s)
	subscribeOrder(t, c, id, token)
	readRealtime(t, c)
	readDone := make(chan error, 1)
	go func() { _, _, err := c.Read(context.Background()); readDone <- err }()
	select {
	case err := <-readDone:
		t.Fatalf("socket prematurely closed: %v", err)
	case <-time.After(11 * time.Second):
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("app did not shut down")
	}
	select {
	case <-readDone:
	case <-time.After(2 * time.Second):
		t.Fatal("hijacked socket survived shutdown")
	}
}

func TestRealtimeCommerceLifecycleEvents(t *testing.T) {
	a, expiredID, _, staff := realtimeFixture(t)
	ctx := context.Background()
	var category, product, qr string
	if err := a.DB.QueryRow(ctx, `insert into public.categories(name,slug) values('WS LIFECYCLE',gen_random_uuid()::text) returning id`).Scan(&category); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if _, err := a.DB.Exec(ctx, "delete from public.categories where id=$1", category); err != nil {
			t.Error(err)
		}
	})
	if err := a.DB.QueryRow(ctx, `insert into public.products(category_id,name,slug,price) values($1,'WS LIFECYCLE',gen_random_uuid()::text,5000) returning id`, category).Scan(&product); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if _, err := a.DB.Exec(ctx, "delete from public.products where id=$1", product); err != nil {
			t.Error(err)
		}
	})
	if err := a.DB.QueryRow(ctx, `select t.qr_token from public.tables t join public.orders o on o.table_id=t.id where o.id=$1`, expiredID).Scan(&qr); err != nil {
		t.Fatal(err)
	}
	items := []map[string]any{{"product_id": product, "quantity": 1, "variant_ids": []string{}, "addon_ids": []string{}}}
	payload, _ := json.Marshal(map[string]any{"table_token": qr, "payment_method": "cash", "items": items})
	capability := "ws-lifecycle-" + expiredID
	var id string
	if err := a.DB.QueryRow(ctx, `select tkm.checkout($1,$2,$3::jsonb)->>'id'`, "ws-lifecycle-"+expiredID, capability, payload).Scan(&id); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		for _, sql := range []string{"delete from tkm.checkout_keys where order_id=$1", "delete from tkm.outbox_events where order_id=$1", "delete from public.payments where order_id=$1", "delete from public.orders where id=$1"} {
			if _, err := a.DB.Exec(ctx, sql, id); err != nil {
				t.Error(err)
			}
		}
	})
	access := staffToken(time.Now().Add(time.Hour))
	mockRealtimeAuth(t, a, staff, access)
	rt, s := realtimeServer(t, RealtimeConfig{API: a})
	cashier := dialRealtime(t, s)
	subscribeStaff(t, cashier, access)
	readRealtime(t, cashier)
	customer := dialRealtime(t, s)
	subscribeOrder(t, customer, id, capability)
	readRealtime(t, customer)
	store := realtimeOutbox(t, a, id)
	publish := func(eventType string, version int) {
		t.Helper()
		if n, err := store.dispatchBatch(ctx, rt, 100); err != nil || n != 1 {
			t.Fatal(n, err)
		}
		for _, c := range []*websocket.Conn{cashier, customer} {
			v := readRealtime(t, c)
			if v["event_type"] != eventType || v["version"] != float64(version) || v["order_id"] != id {
				t.Fatal(v)
			}
		}
	}
	publish("ORDER_CREATED", 1)
	itemJSON, _ := json.Marshal(items)
	if _, err := a.DB.Exec(ctx, `select tkm.review_order($1,$2,1,$3::jsonb)`, id, staff, itemJSON); err != nil {
		t.Fatal(err)
	}
	publish("ORDER_REVIEWED", 2)
	if _, err := a.DB.Exec(ctx, `select tkm.confirm_cash($1,$2,5000,2)`, id, staff); err != nil {
		t.Fatal(err)
	}
	publish("ORDER_PAYMENT_CONFIRMED", 3)
	if _, err := a.DB.Exec(ctx, `select tkm.complete_order($1,$2)`, id, staff); err != nil {
		t.Fatal(err)
	}
	publish("ORDER_COMPLETED", 4)
	if _, err := a.DB.Exec(ctx, `update public.orders set created_at=clock_timestamp()-interval '16 minutes' where id=$1`, expiredID); err != nil {
		t.Fatal(err)
	}
	if _, err := a.DB.Exec(ctx, `select tkm.expire_one($1)`, expiredID); err != nil {
		t.Fatal(err)
	}
	expiryStore := realtimeOutbox(t, a, expiredID)
	if n, err := expiryStore.dispatchBatch(ctx, rt, 100); err != nil || n != 1 {
		t.Fatal(n, err)
	}
	if v := readRealtime(t, cashier); v["event_type"] != "ORDER_EXPIRED" || v["order_id"] != expiredID {
		t.Fatal(v)
	}
	// Customer's authoritative completed REST snapshot remains available.
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/api/v1/orders/"+id, nil)
	r.Header.Set("X-Order-Token", capability)
	NewHandler(a.DB, "").ServeHTTP(w, r)
	var snapshot map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &snapshot); err != nil {
		t.Fatal(err)
	}
	if w.Code != 200 || snapshot["status"] != "completed" || snapshot["version"] != float64(4) {
		t.Fatal(w.Code, snapshot)
	}
}
