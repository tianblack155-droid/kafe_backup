package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"testing"
)

func TestHealth(t *testing.T) {
	h := NewHandler(nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("GET", "/health", nil))
	if w.Code != 200 {
		t.Fatalf("status=%d", w.Code)
	}
	var body map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body["status"] != "ok" {
		t.Fatalf("body=%v", body)
	}
}

type pingFunc func(context.Context) error

func (f pingFunc) Ping(ctx context.Context) error { return f(ctx) }

func TestReadiness(t *testing.T) {
	for _, tc := range []struct {
		name string
		db   Pinger
		code int
	}{
		{"unconfigured", nil, 503},
		{"unreachable", pingFunc(func(context.Context) error { return errors.New("secret db address") }), 503},
		{"healthy", pingFunc(func(ctx context.Context) error {
			if _, ok := ctx.Deadline(); !ok {
				t.Error("ping must have deadline")
			}
			return nil
		}), 200},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			NewHandler(tc.db).ServeHTTP(w, httptest.NewRequest("GET", "/ready", nil))
			if w.Code != tc.code {
				t.Fatalf("status=%d want=%d", w.Code, tc.code)
			}
			var body map[string]string
			if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			if body["error"] == "secret db address" {
				t.Fatal("leaked error")
			}
		})
	}
}
