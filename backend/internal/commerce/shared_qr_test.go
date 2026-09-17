package commerce

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// All fixtures are transaction-local: even a failed checkout cannot leak orders
// or hide missing cleanup behind the now-optional table_id.
func TestSharedQRCheckoutWithoutTable(t *testing.T) {
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
	defer tx.Rollback(ctx)
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	var cat, prod string
	must(tx.QueryRow(ctx, "insert into public.categories(name,slug) values('NO TABLE',gen_random_uuid()::text) returning id").Scan(&cat))
	must(tx.QueryRow(ctx, "insert into public.products(category_id,name,slug,price) values($1,'NO TABLE',gen_random_uuid()::text,10000) returning id", cat).Scan(&prod))
	_, err = tx.Exec(ctx, "set local role tkm_runtime")
	must(err)
	payload := fmt.Sprintf(`{"payment_method":"cash","items":[{"product_id":%q,"quantity":1,"variant_ids":[],"addon_ids":[]}]}`, prod)
	var out []byte
	must(tx.QueryRow(ctx, "select tkm.checkout($1,$2,$3::jsonb)", "no-table-key-"+prod, "no-table-access-"+prod, payload).Scan(&out))
	var order map[string]any
	must(json.Unmarshal(out, &order))
	if order["id"] == nil || order["table_id"] != nil || order["tables"] != nil {
		t.Fatalf("expected tableless order: %s", out)
	}
}

func TestSharedQRRuntimeHTTP(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL required")
	}
	ctx := context.Background()
	management, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer management.Close()
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	var staff, cat, prod, qr string
	must(management.QueryRow(ctx, "insert into public.profiles(id,role) values(gen_random_uuid(),'cashier') returning id").Scan(&staff))
	// Cleanup by attempt identity, never table_id, including orders from failed assertions.
	defer func() {
		rows, e := management.Query(ctx, "select order_id::text from tkm.checkout_keys where key like $1", staff+"%")
		if e != nil {
			t.Error(e)
			return
		}
		ids, e := pgx.CollectRows(rows, pgx.RowTo[string])
		if e != nil {
			t.Error(e)
			return
		}
		for _, query := range []string{
			"delete from tkm.checkout_keys where order_id=any($1::uuid[])",
			"delete from public.payments where order_id=any($1::uuid[])",
			"delete from tkm.outbox_events where order_id=any($1::uuid[])",
			"delete from public.orders where id=any($1::uuid[])",
		} {
			if _, e := management.Exec(ctx, query, ids); e != nil {
				t.Error(e)
			}
		}
		for _, q := range []struct{ sql, id string }{
			{"delete from public.tables where qr_token=$1", qr},
			{"delete from public.products where id=$1", prod},
			{"delete from public.categories where id=$1", cat},
			{"delete from public.profiles where id=$1", staff},
		} {
			if q.id != "" {
				if _, e := management.Exec(ctx, q.sql, q.id); e != nil {
					t.Error(e)
				}
			}
		}
	}()
	must(management.QueryRow(ctx, "insert into public.categories(name,slug) values('NO TABLE HTTP',gen_random_uuid()::text) returning id").Scan(&cat))
	must(management.QueryRow(ctx, "insert into public.products(category_id,name,slug,price) values($1,'NO TABLE HTTP',gen_random_uuid()::text,10000) returning id", cat).Scan(&prod))
	must(management.QueryRow(ctx, "insert into public.tables(number,qr_token) values(99991,gen_random_uuid()::text) returning qr_token").Scan(&qr))
	cfg := management.Config()
	cfg.AfterConnect = func(ctx context.Context, c *pgx.Conn) error { _, e := c.Exec(ctx, "set role tkm_runtime"); return e }
	db, err := pgxpool.NewWithConfig(ctx, cfg)
	must(err)
	defer db.Close()
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer shared-qr-staff" {
			w.WriteHeader(401)
			return
		}
		fmt.Fprintf(w, `{"id":%q}`, staff)
	}))
	defer auth.Close()
	h := NewHandler(db, auth.URL)
	token := "order-capability-" + staff
	call := func(method, path, body, key, capability, bearer string, status int) map[string]any {
		t.Helper()
		w := httptest.NewRecorder()
		r := httptest.NewRequest(method, path, strings.NewReader(body))
		r.Header.Set("Idempotency-Key", staff+key)
		r.Header.Set("X-Order-Token", capability)
		if bearer != "" {
			r.Header.Set("Authorization", "Bearer "+bearer)
		}
		h.ServeHTTP(w, r)
		if w.Code != status {
			t.Fatalf("%s %s: want %d got %d %s", method, path, status, w.Code, w.Body)
		}
		var result map[string]any
		must(json.Unmarshal(w.Body.Bytes(), &result))
		return result
	}
	items := fmt.Sprintf(`[{"product_id":%q,"quantity":1,"variant_ids":[],"addon_ids":[],"notes":""}]`, prod)
	base := fmt.Sprintf(`{"customer_name":"Guest","payment_method":"cash","items":%s}`, items)
	// The final legacy token is inactive after case 3; it too must be ignored.
	for i, field := range []string{"", `,"table_token":""`, `,"table_token":"invalid-table"`, fmt.Sprintf(`,"table_token":%q`, qr), fmt.Sprintf(`,"table_token":%q`, qr)} {
		key := fmt.Sprint(i)
		payload := strings.TrimSuffix(base, "}") + field + "}"
		o := call("POST", "/api/v1/orders", payload, key, token, "", 201)
		if o["id"] == nil || o["table_id"] != nil || o["tables"] != nil {
			t.Fatal(o)
		}
		id := o["id"].(string)
		path := "/api/v1/orders/" + id
		// The capability is the order secret, never the legacy table credential.
		call("GET", path, "", key, qr, "", 404)
		call("GET", path, "", key, "", "", 404)
		call("GET", path, "", key, token, "", 200)
		retry := call("POST", "/api/v1/orders", payload, key, token, "", 201)
		if retry["id"] != id {
			t.Fatal("duplicate order")
		}
		call("POST", "/api/v1/orders", payload, key, token+"wrong", "", 409)
		call("POST", "/api/v1/orders", strings.Replace(payload, `"quantity":1`, `"quantity":2`, 1), key, token, "", 409)
		var stored []byte
		must(management.QueryRow(ctx, "select payload from tkm.checkout_keys where key=$1", staff+key).Scan(&stored))
		var p map[string]any
		must(json.Unmarshal(stored, &p))
		if _, ok := p["table_token"]; !ok {
			t.Fatal("serialized empty table_token removed: old idempotency identity changed")
		}
		if i == 0 {
			// Omitted and explicitly empty still serialize to the same existing identity.
			call("POST", "/api/v1/orders", strings.TrimSuffix(base, "}")+`,"table_token":""}`, key, token, "", 201)
			call("POST", "/api/v1/orders", strings.TrimSuffix(base, "}")+`,"table_token":"different"}`, key, token, "", 409)
			call("GET", path+"/reorder", "", key, token, "", 409)
			call("POST", path+"/review", `{"expected_version":1,"items":`+items+`}`, key, token, "bad", 401)
			call("POST", path+"/confirm-cash", `{"received_rp":10000,"expected_version":1}`, key, token, "shared-qr-staff", 409)
			call("POST", path+"/complete", `{}`, key, token, "shared-qr-staff", 409)
			reviewed := call("POST", path+"/review", `{"expected_version":1,"items":`+items+`}`, key, token, "shared-qr-staff", 200)
			if reviewed["table_id"] != nil || reviewed["tables"] != nil || reviewed["total"] != o["total"] || reviewed["expires_at"] != o["expires_at"] {
				t.Fatal(reviewed)
			}
			call("POST", path+"/review", `{"expected_version":1,"items":`+items+`}`, key, token, "shared-qr-staff", 409)
			call("POST", path+"/confirm-cash", `{"received_rp":1,"expected_version":2}`, key, token, "shared-qr-staff", 409)
			cash := fmt.Sprintf(`{"received_rp":%.0f,"expected_version":2}`, o["total"])
			call("POST", path+"/confirm-cash", cash, key, token, "shared-qr-staff", 200)
			call("POST", path+"/confirm-cash", cash, key, token, "shared-qr-staff", 200)
			done := call("POST", path+"/complete", `{}`, key, token, "shared-qr-staff", 200)
			if done["status"] != "completed" {
				t.Fatal(done)
			}
		} else {
			if i == 3 {
				// Represent a retained historical table reference. The SQL migration
				// regression separately creates a real pre-0005 checkout and verifies
				// its snapshot/payload across the actual migration.
				_, err = management.Exec(ctx, "update public.orders set table_id=(select id from public.tables where qr_token=$2) where id=$1", id, qr)
				must(err)
				_, err = management.Exec(ctx, "update public.tables set is_active=false where qr_token=$1", qr)
				must(err)
				historical := call("GET", path, "", key, token, "", 200)
				if historical["table_id"] == nil || historical["tables"].(map[string]any)["number"] != float64(99991) {
					t.Fatal(historical)
				}
				reviewed := call("POST", path+"/review", `{"expected_version":1,"items":`+items+`}`, key, token, "shared-qr-staff", 200)
				if reviewed["table_id"] != historical["table_id"] {
					t.Fatal("legacy reference changed", reviewed)
				}
				recovered := call("POST", "/api/v1/orders", payload, key, token, "", 201)
				if recovered["id"] != id || recovered["version"] != reviewed["version"] {
					t.Fatal(recovered)
				}
				var unchanged bool
				must(management.QueryRow(ctx, "select payload=$2::jsonb from tkm.checkout_keys where key=$1", staff+key, stored).Scan(&unchanged))
				if !unchanged {
					t.Fatal("legacy stored payload changed")
				}
			}
			_, err = management.Exec(ctx, "update public.orders set created_at=clock_timestamp()-interval '16 minutes' where id=$1", id)
			must(err)
			expired := call("GET", path, "", key, token, "", 200)
			if expired["status"] != "expired" {
				t.Fatal(expired)
			}
			call("POST", path+"/review", `{"expected_version":1,"items":`+items+`}`, key, token, "shared-qr-staff", 409)
			call("POST", path+"/confirm-cash", `{"received_rp":10000,"expected_version":1}`, key, token, "shared-qr-staff", 409)
			call("GET", path+"/reorder", "", key, "", "", 404)
			reordered := call("GET", path+"/reorder", "", key, token, "", 200)
			if _, ok := reordered["table_token"]; ok {
				t.Fatal("reorder retained table identity", reordered)
			}
			b, e := json.Marshal(reordered)
			must(e)
			fresh := call("POST", "/api/v1/orders", string(b), key+"reorder", token, "", 201)
			if fresh["id"] == id || fresh["table_id"] != nil || fresh["tables"] != nil {
				t.Fatal(fresh)
			}
		}
	}
}
