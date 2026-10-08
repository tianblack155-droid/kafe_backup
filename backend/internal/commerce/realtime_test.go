package commerce

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/jackc/pgx/v5/pgxpool"
)

const localOrigin = "http://localhost:3000"

func TestRealtimeDefaultsAndAPIIsolation(t *testing.T) {
	a := &API{AuthURL: "http://auth.test"}
	rt, err := NewRealtime(RealtimeConfig{API: a, Origins: []string{localOrigin}, MaxConnections: 1000, MaxPerIdentity: 100, QueueSize: 1000})
	if err != nil {
		t.Fatal(err)
	}
	defer rt.Close()
	if rt.cfg.API.Client == nil {
		t.Fatal("missing default HTTP client")
	}
	if a.Client != nil {
		t.Fatal("constructor mutated caller's API")
	}
	if rt.cfg.MaxConnections != 100 || rt.cfg.MaxPerIdentity != 5 || rt.cfg.QueueSize != 32 || rt.cfg.AuthTimeout != 5*time.Second || rt.cfg.RevalidateInterval != 30*time.Second {
		t.Fatal("unsafe defaults", rt.cfg)
	}
}

func TestRealtimeHandshakeGuard(t *testing.T) {
	rt, err := NewRealtime(RealtimeConfig{Origins: []string{localOrigin}})
	if err != nil {
		t.Fatal(err)
	}
	defer rt.Close()
	for _, tc := range []struct {
		origin, query string
		code          int
	}{{"", "", 403}, {"null", "", 403}, {"http://foreign", "", 403}, {localOrigin, "?access_token=secret", 400}, {localOrigin, "?", 400}} {
		w := httptest.NewRecorder()
		r := httptest.NewRequest("GET", "/api/v1/realtime"+tc.query, nil)
		r.Header.Set("Origin", tc.origin)
		rt.ServeHTTP(w, r)
		if w.Code != tc.code {
			t.Errorf("%q %q: %d", tc.origin, tc.query, w.Code)
		}
	}
	disabled, err := NewRealtime(RealtimeConfig{})
	if err != nil {
		t.Fatal(err)
	}
	defer disabled.Close()
	w := httptest.NewRecorder()
	disabled.ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/realtime", nil))
	if w.Code != 404 {
		t.Fatal(w.Code)
	}
}

// Fixtures are management-only, targeted by generated IDs. No worker is started
// by these socket tests; unrelated durable events are never consumed.
func realtimeFixture(t *testing.T) (*API, string, string, string) {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL required")
	}
	db, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(db.Close)
	ctx := context.Background()
	var table, order, staff string
	if err = db.QueryRow(ctx, `insert into public.tables(number,qr_token) values(99990,gen_random_uuid()::text) returning id`).Scan(&table); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if _, err := db.Exec(ctx, "delete from public.tables where id=$1", table); err != nil {
			t.Error(err)
		}
	})
	if err = db.QueryRow(ctx, `insert into public.orders(table_id) values($1) returning id`, table).Scan(&order); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		for _, sql := range []string{"delete from tkm.checkout_keys where order_id=$1", "delete from tkm.outbox_events where order_id=$1", "delete from public.orders where id=$1"} {
			if _, err := db.Exec(ctx, sql, order); err != nil {
				t.Error(err)
			}
		}
	})
	token := "capability-" + order
	hash := sha256.Sum256([]byte(token))
	if _, err = db.Exec(ctx, `insert into tkm.checkout_keys(key,payload,access_hash,order_id) values($1,'{}',$2,$3)`, "ws-"+order, hex.EncodeToString(hash[:]), order); err != nil {
		t.Fatal(err)
	}
	if err = db.QueryRow(ctx, `insert into public.profiles(id,role) values(gen_random_uuid(),'cashier') returning id`).Scan(&staff); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if _, err := db.Exec(ctx, "delete from public.profiles where id=$1", staff); err != nil {
			t.Error(err)
		}
	})
	return &API{DB: db, Client: http.DefaultClient}, order, token, staff
}
func realtimeServer(t *testing.T, cfg RealtimeConfig) (*Realtime, *httptest.Server) {
	t.Helper()
	cfg.Origins = []string{localOrigin}
	rt, err := NewRealtime(cfg)
	if err != nil {
		t.Fatal(err)
	}
	s := httptest.NewServer(rt.Handler(NewHandler(cfg.API.DB, "")))
	t.Cleanup(s.Close)
	t.Cleanup(rt.Close)
	return rt, s
}
func dialRealtime(t *testing.T, s *httptest.Server) *websocket.Conn {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(s.URL, "http")+"/api/v1/realtime", &websocket.DialOptions{HTTPHeader: http.Header{"Origin": {localOrigin}}, CompressionMode: websocket.CompressionContextTakeover})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.CloseNow() })
	return c
}
func subscribeOrder(t *testing.T, c *websocket.Conn, id, token string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := wsjson.Write(ctx, c, map[string]string{"type": "subscribe", "channel": "order", "order_id": id, "order_token": token}); err != nil {
		t.Fatal(err)
	}
}
func readRealtime(t *testing.T, c *websocket.Conn) map[string]any {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	var v map[string]any
	if err := wsjson.Read(ctx, c, &v); err != nil {
		t.Fatal(err)
	}
	return v
}
func expectRealtimeClosed(t *testing.T, c *websocket.Conn) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, _, err := c.Read(ctx)
	if err == nil || ctx.Err() != nil {
		t.Fatalf("expected prompt server close, got %v", err)
	}
}
func TestRealtimeCustomerCapability(t *testing.T) {
	a, id, token, _ := realtimeFixture(t)
	_, s := realtimeServer(t, RealtimeConfig{API: a})
	for _, tc := range []struct{ id, token string }{{id, ""}, {id, "wrong"}, {"00000000-0000-0000-0000-000000000000", token}, {"not-uuid", token}} {
		c := dialRealtime(t, s)
		subscribeOrder(t, c, tc.id, tc.token)
		expectRealtimeClosed(t, c)
	}
	c := dialRealtime(t, s)
	subscribeOrder(t, c, id, token)
	if v := readRealtime(t, c); len(v) != 1 || v["type"] != "ready" {
		t.Fatal(v)
	}
	// A second subscription (even identical) is not a mutation or reauth API.
	subscribeOrder(t, c, id, token)
	expectRealtimeClosed(t, c)
}
func TestRealtimeFirstFrame(t *testing.T) {
	a, _, _, _ := realtimeFixture(t)
	_, s := realtimeServer(t, RealtimeConfig{API: a, AuthTimeout: 50 * time.Millisecond})
	c := dialRealtime(t, s)
	expectRealtimeClosed(t, c)
	for _, tc := range []struct {
		kind websocket.MessageType
		body string
	}{{websocket.MessageBinary, `{}`}, {websocket.MessageText, strings.Repeat("x", 12*1024+1)}, {websocket.MessageText, `{"type":"mutate"}`}, {websocket.MessageText, `{} {}`}, {websocket.MessageText, `{"type":"subscribe","channel":"order","unknown":true}`}} {
		c := dialRealtime(t, s)
		_ = c.Write(context.Background(), tc.kind, []byte(tc.body))
		expectRealtimeClosed(t, c)
	}
}

func staffToken(exp time.Time) string {
	b, _ := json.Marshal(map[string]any{"exp": exp.Unix()})
	return "eyJhbGciOiJIUzI1NiJ9." + base64.RawURLEncoding.EncodeToString(b) + ".test-signature"
}
func mockRealtimeAuth(t *testing.T, a *API, staff, token string) *atomic.Bool {
	t.Helper()
	allowed := new(atomic.Bool)
	allowed.Store(true)
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/auth/v1/user" || r.Header.Get("Authorization") != "Bearer "+token || !allowed.Load() {
			w.WriteHeader(401)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]string{"id": staff})
	}))
	t.Cleanup(auth.Close)
	a.AuthURL = auth.URL
	return allowed
}
func subscribeStaff(t *testing.T, c *websocket.Conn, token string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := wsjson.Write(ctx, c, map[string]string{"type": "subscribe", "channel": "cashier", "access_token": token}); err != nil {
		t.Fatal(err)
	}
}
func TestRealtimeStaffAndRevocation(t *testing.T) {
	a, id, capability, staff := realtimeFixture(t)
	token := staffToken(time.Now().Add(time.Hour))
	allowed := mockRealtimeAuth(t, a, staff, token)
	_, s := realtimeServer(t, RealtimeConfig{API: a, RevalidateInterval: 30 * time.Millisecond})
	c := dialRealtime(t, s)
	subscribeStaff(t, c, "forged")
	expectRealtimeClosed(t, c)
	c = dialRealtime(t, s)
	subscribeStaff(t, c, token)
	if v := readRealtime(t, c); v["type"] != "ready" {
		t.Fatal(v)
	}
	allowed.Store(false)
	expectRealtimeClosed(t, c)
	allowed.Store(true)
	c = dialRealtime(t, s)
	subscribeStaff(t, c, token)
	readRealtime(t, c)
	if _, err := a.DB.Exec(context.Background(), "delete from public.profiles where id=$1", staff); err != nil {
		t.Fatal(err)
	}
	expectRealtimeClosed(t, c)
	c = dialRealtime(t, s)
	subscribeStaff(t, c, token)
	expectRealtimeClosed(t, c)
	c = dialRealtime(t, s)
	subscribeOrder(t, c, id, capability)
	readRealtime(t, c)
	if _, err := a.DB.Exec(context.Background(), "delete from tkm.checkout_keys where order_id=$1", id); err != nil {
		t.Fatal(err)
	}
	expectRealtimeClosed(t, c)
}
func TestRealtimeStaffExpiry(t *testing.T) {
	a, _, _, staff := realtimeFixture(t)
	token := staffToken(time.Now().Add(time.Second))
	mockRealtimeAuth(t, a, staff, token)
	_, s := realtimeServer(t, RealtimeConfig{API: a, RevalidateInterval: time.Hour})
	c := dialRealtime(t, s)
	subscribeStaff(t, c, token)
	readRealtime(t, c)
	expectRealtimeClosed(t, c)
	c = dialRealtime(t, s)
	subscribeStaff(t, c, token)
	expectRealtimeClosed(t, c)
}
func TestRealtimeScopedMinimalDispatch(t *testing.T) {
	a, id, token, staff := realtimeFixture(t)
	access := staffToken(time.Now().Add(time.Hour))
	mockRealtimeAuth(t, a, staff, access)
	rt, s := realtimeServer(t, RealtimeConfig{API: a})
	customer := dialRealtime(t, s)
	subscribeOrder(t, customer, id, token)
	readRealtime(t, customer)
	cashier := dialRealtime(t, s)
	subscribeStaff(t, cashier, access)
	readRealtime(t, cashier)
	foreign := Invalidation{Type: "order.changed", EventID: "00000000-0000-0000-0000-000000000001", OrderID: "00000000-0000-0000-0000-000000000002", Version: 2, EventType: "ORDER_REVIEWED"}
	rt.dispatch(foreign)
	own := Invalidation{Type: "order.changed", EventID: "00000000-0000-0000-0000-000000000003", OrderID: id, Version: 3, EventType: "ORDER_REVIEWED"}
	rt.dispatch(own)
	if v := readRealtime(t, cashier); v["order_id"] != foreign.OrderID {
		t.Fatal(v)
	}
	for _, c := range []*websocket.Conn{customer, cashier} {
		v := readRealtime(t, c)
		if len(v) != 5 || v["type"] != "order.changed" || v["event_id"] != own.EventID || v["order_id"] != id || v["version"] != float64(3) || v["event_type"] != "ORDER_REVIEWED" {
			t.Fatal(v)
		}
	}
}
func TestRealtimeLimitsAndShutdown(t *testing.T) {
	a, id, token, _ := realtimeFixture(t)
	rt, s := realtimeServer(t, RealtimeConfig{API: a, MaxConnections: 3, MaxPerIdentity: 1})
	c := dialRealtime(t, s)
	subscribeOrder(t, c, id, token)
	readRealtime(t, c)
	extra := dialRealtime(t, s)
	subscribeOrder(t, extra, id, token)
	expectRealtimeClosed(t, extra)
	idle1 := dialRealtime(t, s)
	idle2 := dialRealtime(t, s)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	denied, res, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(s.URL, "http")+"/api/v1/realtime", &websocket.DialOptions{HTTPHeader: http.Header{"Origin": {localOrigin}}})
	if denied != nil {
		denied.CloseNow()
	}
	if err == nil || res == nil || res.StatusCode != 503 {
		t.Fatalf("global bound: %v %v", res, err)
	}
	rt.Close()
	expectRealtimeClosed(t, c)
	expectRealtimeClosed(t, idle1)
	expectRealtimeClosed(t, idle2)
}
func TestRealtimeQueueOverflow(t *testing.T) {
	rt, err := NewRealtime(RealtimeConfig{})
	if err != nil {
		t.Fatal(err)
	}
	defer rt.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	p := &realtimePeer{sub: subscription{Channel: "cashier"}, queue: make(chan Invalidation, 1), cancel: cancel}
	rt.peers[p] = true
	rt.dispatch(Invalidation{Type: "order.changed"})
	rt.dispatch(Invalidation{Type: "order.changed"})
	select {
	case <-ctx.Done():
	case <-time.After(time.Second):
		t.Fatal("overflow did not disconnect")
	}
}
func TestRealtimeOutlivesRESTTimeoutAndHeartbeat(t *testing.T) {
	a, id, token, _ := realtimeFixture(t)
	_, s := realtimeServer(t, RealtimeConfig{API: a, PingInterval: 30 * time.Millisecond, WriteTimeout: 100 * time.Millisecond})
	c := dialRealtime(t, s)
	subscribeOrder(t, c, id, token)
	readRealtime(t, c)
	ctx, cancel := context.WithTimeout(context.Background(), 9*time.Second)
	defer cancel()
	// Continuous read answers ping. Only our 9s test deadline may end the socket.
	_, _, err := c.Read(ctx)
	if ctx.Err() != context.DeadlineExceeded {
		t.Fatalf("socket ended before REST deadline: %v", err)
	}
	silent := dialRealtime(t, s)
	subscribeOrder(t, silent, id, token)
	readRealtime(t, silent)
	time.Sleep(200 * time.Millisecond)
	expectRealtimeClosed(t, silent)
}
