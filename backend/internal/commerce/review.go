package commerce

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"github.com/jackc/pgx/v5/pgxpool"
	"log/slog"
	"net/http"
	"time"
)

func writeOrderResult(w http.ResponseWriter, data []byte) {
	var result struct {
		Error string `json:"error"`
	}
	if json.Unmarshal(data, &result) != nil {
		writeError(w, 503, "Invalid order response")
		return
	}
	if result.Error != "" {
		writeError(w, 409, result.Error)
		return
	}
	_, _ = w.Write(data)
}
func (a *API) review(w http.ResponseWriter, r *http.Request) {
	actor, err := a.staff(r)
	if err != nil {
		writeError(w, 401, "Staff login required")
		return
	}
	var p struct {
		ExpectedVersion int             `json:"expected_version"`
		Items           json.RawMessage `json:"items"`
	}
	if !decode(w, r, &p) {
		return
	}
	var data []byte
	err = a.DB.QueryRow(r.Context(), "select tkm.review_order($1,$2,$3,$4::jsonb)", r.PathValue("id"), actor, p.ExpectedVersion, []byte(p.Items)).Scan(&data)
	if err != nil {
		dbError(w, err)
		return
	}
	writeOrderResult(w, data)
}
func (a *API) canReadOrder(r *http.Request) bool {
	hash := sha256.Sum256([]byte(r.Header.Get("X-Order-Token")))
	var found bool
	err := a.DB.QueryRow(r.Context(), "select exists(select 1 from tkm.checkout_keys where order_id=$1 and access_hash=$2)", r.PathValue("id"), hex.EncodeToString(hash[:])).Scan(&found)
	return err == nil && found
}
func (a *API) reorder(w http.ResponseWriter, r *http.Request) {
	if !a.canReadOrder(r) {
		if _, err := a.staff(r); err != nil {
			writeError(w, 404, "Order not found")
			return
		}
	}
	var expired bool
	if err := a.DB.QueryRow(r.Context(), "select tkm.expire_one($1)", r.PathValue("id")).Scan(&expired); err != nil {
		dbError(w, err)
		return
	}
	if !expired {
		writeError(w, 409, "Only expired orders can be reordered")
		return
	}
	var data []byte
	err := a.DB.QueryRow(r.Context(), `select jsonb_build_object('customer_name',coalesce(o.customer_name,''),'payment_method','cash','items',coalesce((select jsonb_agg(jsonb_build_object('product_id',i.product_id,'quantity',i.quantity,'variant_ids',i.variant_ids,'addon_ids',i.addon_ids,'notes',coalesce(i.notes,''))) from public.order_items i where i.order_id=o.id),'[]'::jsonb)) from public.orders o where o.id=$1`, r.PathValue("id")).Scan(&data)
	if err != nil {
		dbError(w, err)
		return
	}
	_, _ = w.Write(data)
}

// Persist overdue state even without traffic. Payment also checks under row lock.
func RunExpiry(ctx context.Context, db *pgxpool.Pool, logger *slog.Logger) {
	if db == nil {
		return
	}
	tick := time.NewTicker(5 * time.Second)
	defer tick.Stop()
	for {
		sweepCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
		_, err := db.Exec(sweepCtx, "select tkm.expire_orders()")
		cancel()
		if err != nil && ctx.Err() == nil {
			logger.Warn("order expiry sweep failed")
		}
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
	}
}
