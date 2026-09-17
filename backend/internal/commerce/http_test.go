package commerce

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestRoutesFailClosedWithoutDatabase(t *testing.T) {
	h := NewHandler(nil, "")
	for _, path := range []string{"/api/v1/menu", "/api/v1/orders", "/api/v1/orders/00000000-0000-0000-0000-000000000000"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 503 {
			t.Fatalf("%s: %d", path, w.Code)
		}
	}
}

func TestMenuIntegration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL required")
	}
	db, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	h := NewHandler(db, "")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/menu", nil))
	if w.Code != 200 {
		t.Fatalf("menu %d %s", w.Code, w.Body)
	}
	var data struct {
		Settings struct {
			Brand string `json:"brand_name"`
		}
		Products []any
	}
	if err := json.Unmarshal(w.Body.Bytes(), &data); err != nil {
		t.Fatal(err)
	}
	if data.Settings.Brand != "TerasKayuManis" {
		t.Fatal(data.Settings.Brand)
	}
}

func TestCashHTTPIntegration(t *testing.T) {
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
	var staff, cat, prod, table string
	db.QueryRow(ctx, "insert into public.profiles(id,role) values(gen_random_uuid(),'cashier') returning id").Scan(&staff)
	db.QueryRow(ctx, "insert into public.categories(name,slug) values('HTTP TEST',gen_random_uuid()::text) returning id").Scan(&cat)
	db.QueryRow(ctx, "insert into public.products(category_id,name,slug,price) values($1,'HTTP TEST',gen_random_uuid()::text,10000) returning id", cat).Scan(&prod)
	db.QueryRow(ctx, "insert into public.tables(number,qr_token) values(99998,gen_random_uuid()::text) returning qr_token").Scan(&table)
	defer func() {
		db.Exec(ctx, "delete from public.tables where number=99998")
		db.Exec(ctx, "delete from public.products where id=$1", prod)
		db.Exec(ctx, "delete from public.categories where id=$1", cat)
		db.Exec(ctx, "delete from public.profiles where id=$1", staff)
	}()
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-staff" {
			w.WriteHeader(401)
			return
		}
		fmt.Fprintf(w, `{"id":%q}`, staff)
	}))
	defer auth.Close()
	h := NewHandler(db, auth.URL)
	call := func(method, path, body, token string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		r := httptest.NewRequest(method, path, strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token)
		r.Header.Set("Idempotency-Key", "http-key-"+staff)
		r.Header.Set("X-Order-Token", "http-access-"+staff)
		h.ServeHTTP(w, r)
		return w
	}
	payload := fmt.Sprintf(`{"table_token":%q,"payment_method":"cash","items":[{"product_id":%q,"quantity":1,"variant_ids":[],"addon_ids":[]}]}`, table, prod)
	// A catalog rejection rolls back both the order and its attempt identity.
	db.Exec(ctx, "update public.products set is_available=false where id=$1", prod)
	rejected := call("POST", "/api/v1/orders", payload, "")
	if rejected.Code != 409 || !strings.Contains(rejected.Body.String(), `"code":"checkout_rejected"`) {
		t.Fatalf("definitive rejection %d %s", rejected.Code, rejected.Body)
	}
	var attempts int
	if err := db.QueryRow(ctx, "select count(*) from tkm.checkout_keys where key=$1", "http-key-"+staff).Scan(&attempts); err != nil || attempts != 0 {
		t.Fatal("rejected attempt persisted", attempts, err)
	}
	db.Exec(ctx, "update public.products set is_available=true where id=$1", prod)
	w := call("POST", "/api/v1/orders", payload, "")
	if w.Code != 201 {
		t.Fatalf("create %d %s", w.Code, w.Body)
	}
	var order struct {
		ID string `json:"id"`
	}
	json.Unmarshal(w.Body.Bytes(), &order)
	defer func() {
		db.Exec(ctx, "delete from tkm.checkout_keys where order_id=$1", order.ID)
		db.Exec(ctx, "delete from tkm.outbox_events where order_id=$1", order.ID)
		db.Exec(ctx, "delete from public.payments where order_id=$1", order.ID)
		db.Exec(ctx, "delete from public.orders where id=$1", order.ID)
	}()
	if w = call("POST", "/api/v1/orders", payload, ""); w.Code != 201 || !strings.Contains(w.Body.String(), order.ID) {
		t.Fatal("retry failed", w.Body)
	}
	conflicting := strings.Replace(payload, `"quantity":1`, `"quantity":2`, 1)
	if w = call("POST", "/api/v1/orders", conflicting, ""); w.Code != 409 || !strings.Contains(w.Body.String(), `"code":"idempotency_conflict"`) {
		t.Fatal("identity conflict must not release pending", w.Code, w.Body)
	}
	db.Exec(ctx, "update public.products set is_available=false where id=$1", prod)
	if w = call("POST", "/api/v1/orders", payload, ""); w.Code != 201 || !strings.Contains(w.Body.String(), order.ID) {
		t.Fatal("committed retry must bypass changed catalog", w.Code, w.Body)
	}
	db.Exec(ctx, "update public.products set is_available=true where id=$1", prod)
	if w = call("POST", "/api/v1/orders/"+order.ID+"/complete", "{}", "test-staff"); w.Code != 409 {
		t.Fatal("unpaid completion accepted", w.Code)
	}
	if w = call("POST", "/api/v1/orders/"+order.ID+"/confirm-cash", `{"received_rp":10000}`, "wrong"); w.Code != 401 {
		t.Fatal("bad auth", w.Code)
	}
	if w = call("POST", "/api/v1/orders/"+order.ID+"/confirm-cash", `{"received_rp":10000,"expected_version":1}`, "test-staff"); w.Code != 409 {
		t.Fatal("unreviewed payment", w.Code, w.Body)
	}
	review := fmt.Sprintf(`{"expected_version":1,"items":[{"product_id":%q,"quantity":1,"variant_ids":[],"addon_ids":[],"notes":""}]}`, prod)
	if w = call("POST", "/api/v1/orders/"+order.ID+"/review", review, "test-staff"); w.Code != 200 {
		t.Fatal("review", w.Code, w.Body)
	}
	if w = call("POST", "/api/v1/orders/"+order.ID+"/confirm-cash", `{"received_rp":10000,"expected_version":2}`, "test-staff"); w.Code != 200 {
		t.Fatal("payment", w.Code, w.Body)
	}
	if w = call("POST", "/api/v1/orders/"+order.ID+"/complete", "{}", "test-staff"); w.Code != 200 {
		t.Fatal("complete", w.Code, w.Body)
	}
	if w = call("GET", "/api/v1/admin/orders?tab=active", "", "test-staff"); w.Code != 200 || strings.Contains(w.Body.String(), order.ID) {
		t.Fatal("completed in active", w.Code, w.Body)
	}
	if w = call("GET", "/api/v1/admin/orders?tab=history", "", "test-staff"); w.Code != 200 || !strings.Contains(w.Body.String(), order.ID) {
		t.Fatal("missing history", w.Code, w.Body)
	}
	// Separate expired fixture, preserving the original order.
	var expiredID string
	err = db.QueryRow(ctx, "select tkm.checkout($1,$2,$3::jsonb)->>'id'", "expire-key-"+staff, "http-access-"+staff, payload).Scan(&expiredID)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		db.Exec(ctx, "delete from tkm.checkout_keys where order_id=$1", expiredID)
		db.Exec(ctx, "delete from tkm.outbox_events where order_id=$1", expiredID)
		db.Exec(ctx, "delete from public.orders where id=$1", expiredID)
	}()
	db.Exec(ctx, "update public.orders set created_at=clock_timestamp()-interval '15 minutes' where id=$1", expiredID)
	if w = call("GET", "/api/v1/orders/"+expiredID, "", ""); w.Code != 200 || !strings.Contains(w.Body.String(), `"status": "expired"`) {
		t.Fatal("customer expiry", w.Code, w.Body)
	}
	if w = call("GET", "/api/v1/orders/"+expiredID+"/reorder", "", ""); w.Code != 200 || !strings.Contains(w.Body.String(), prod) {
		t.Fatal("reorder payload", w.Code, w.Body)
	}
	unauth := httptest.NewRecorder()
	h.ServeHTTP(unauth, httptest.NewRequest("GET", "/api/v1/orders/"+expiredID+"/reorder", nil))
	if unauth.Code != 404 {
		t.Fatal("capability bypass", unauth.Code)
	}
	if w = call("GET", "/api/v1/admin/orders?tab=history&status=expired", "", "test-staff"); w.Code != 200 || !strings.Contains(w.Body.String(), expiredID) || strings.Contains(w.Body.String(), order.ID) {
		t.Fatal("expiry filter", w.Code, w.Body)
	}
}
