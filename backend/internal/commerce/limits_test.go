package commerce

import (
	"net/http/httptest"
	"testing"
)

func TestRateLimitBoundedGlobal(t *testing.T) {
	h := NewHandler(nil, "")
	limited := false
	for i := 0; i < 301; i++ {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", "/api/v1/menu", nil))
		if w.Code == 429 {
			limited = true
		}
	}
	if !limited {
		t.Fatal("missing request budget")
	}
}
