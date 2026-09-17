package config

import "testing"

func TestRealtimeOrigins(t *testing.T) {
	for _, raw := range []string{"", "  ", "https://cafe.example", "https://cafe.example, http://localhost:3000"} {
		c, err := Load(func(k string) string {
			if k == "REALTIME_ORIGINS" {
				return raw
			}
			return ""
		})
		if err != nil {
			t.Fatalf("%q: %v", raw, err)
		}
		if raw == "https://cafe.example, http://localhost:3000" && (len(c.RealtimeOrigins) != 2 || c.RealtimeOrigins[1] != "http://localhost:3000") {
			t.Fatal(c.RealtimeOrigins)
		}
	}
	for _, raw := range []string{"null", "*", "https://*.example", "ftp://example", "https://example/", "https://example/path", "https://user@example", "https://example?x", "https://example#x", "https://example,", "https://example:bad", "https://example?", "https://example#"} {
		if _, err := Load(func(k string) string {
			if k == "REALTIME_ORIGINS" {
				return raw
			}
			return ""
		}); err == nil {
			t.Errorf("accepted %q", raw)
		}
	}
}
