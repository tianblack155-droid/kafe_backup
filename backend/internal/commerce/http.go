package commerce

import (
	"context"
	"encoding/json"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"sync"
	"time"
)

type API struct {
	DB      *pgxpool.Pool
	AuthURL string
	AuthKey string
	Client  *http.Client
}

func NewHandler(db *pgxpool.Pool, authURL string, keys ...string) http.Handler {
	a := &API{DB: db, AuthURL: authURL, Client: http.DefaultClient}
	if len(keys) > 0 {
		a.AuthKey = keys[0]
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/menu", a.menu)
	mux.HandleFunc("GET /api/v1/table", a.table)
	mux.HandleFunc("POST /api/v1/orders", a.checkout)
	mux.HandleFunc("GET /api/v1/orders/{id}", a.order)
	mux.HandleFunc("GET /api/v1/admin/orders", a.listOrders)
	mux.HandleFunc("POST /api/v1/orders/{id}/confirm-cash", a.confirmCash)
	mux.HandleFunc("POST /api/v1/orders/{id}/complete", a.complete)
	mux.HandleFunc("POST /api/v1/orders/{id}/review", a.review)
	mux.HandleFunc("GET /api/v1/orders/{id}/reorder", a.reorder)
	var budgetMu sync.Mutex
	window := time.Now()
	requests := 0
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		budgetMu.Lock()
		if time.Since(window) >= time.Minute {
			window = time.Now()
			requests = 0
		}
		requests++
		allowed := requests <= 300
		budgetMu.Unlock()
		if !allowed {
			w.Header().Set("Retry-After", "60")
			writeError(w, 429, "Request budget exceeded")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
		defer cancel()
		r = r.WithContext(ctx)
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		if a.DB == nil {
			writeError(w, 503, "Database not configured")
			return
		}
		mux.ServeHTTP(w, r)
	})
}
func writeError(w http.ResponseWriter, code int, message string) {
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": message})
}
func (a *API) menu(w http.ResponseWriter, r *http.Request) {
	var data []byte
	err := a.DB.QueryRow(r.Context(), `select jsonb_build_object(
 'settings',(select to_jsonb(s) from public.settings s where id=1),
 'categories',coalesce((select jsonb_agg(to_jsonb(c) order by sort_order) from public.categories c where is_active),'[]'::jsonb),
 'products',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object(
 'variants',coalesce((select jsonb_agg(to_jsonb(v) order by sort_order) from public.product_variants v where product_id=p.id),'[]'::jsonb),
 'addons',coalesce((select jsonb_agg(to_jsonb(a)) from public.addons a join public.product_addons pa on pa.addon_id=a.id where pa.product_id=p.id),'[]'::jsonb)
 )) from public.products p join public.categories c on c.id=p.category_id where c.is_active),'[]'::jsonb))`).Scan(&data)
	if err != nil {
		writeError(w, 503, "Menu unavailable")
		return
	}
	_, _ = w.Write(data)
}
