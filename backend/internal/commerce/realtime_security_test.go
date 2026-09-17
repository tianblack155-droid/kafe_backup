package commerce

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestRealtimeUppercaseUUIDScope(t *testing.T) {
	a, id, token, _ := realtimeFixture(t)
	rt, s := realtimeServer(t, RealtimeConfig{API: a})
	c := dialRealtime(t, s)
	subscribeOrder(t, c, strings.ToUpper(id), token)
	readRealtime(t, c)
	rt.dispatch(Invalidation{Type: "order.changed", OrderID: id, EventID: id, Version: 1, EventType: "ORDER_CREATED"})
	if v := readRealtime(t, c); v["order_id"] != id {
		t.Fatal(v)
	}
}
func TestRealtimeAuthDeadlineAndMalformedStaffExpiry(t *testing.T) {
	a, _, _, _ := realtimeFixture(t)
	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { <-r.Context().Done() }))
	defer auth.Close()
	a.AuthURL = auth.URL
	_, s := realtimeServer(t, RealtimeConfig{API: a, AuthTimeout: 40 * time.Millisecond})
	c := dialRealtime(t, s)
	subscribeStaff(t, c, staffToken(time.Now().Add(time.Hour)))
	expectRealtimeClosed(t, c)
	for _, token := range []string{"", "not.jwt", "e30.e30.signature", staffToken(time.Now().Add(-time.Hour)), strings.Repeat("x", 8192)} {
		c := dialRealtime(t, s)
		subscribeStaff(t, c, token)
		expectRealtimeClosed(t, c)
	}
}
func TestRealtimeTableQRIsNotCapability(t *testing.T) {
	a, id, _, _ := realtimeFixture(t)
	_, s := realtimeServer(t, RealtimeConfig{API: a})
	var qr string
	if err := a.DB.QueryRow(context.Background(), `select qr_token from public.tables where id=(select table_id from public.orders where id=$1)`, id).Scan(&qr); err != nil {
		t.Fatal(err)
	}
	c := dialRealtime(t, s)
	subscribeOrder(t, c, id, qr)
	expectRealtimeClosed(t, c)
}
