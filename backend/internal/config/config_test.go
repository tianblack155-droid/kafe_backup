package config

import "testing"

func TestLoad(t *testing.T) {
	c, err := Load(func(string) string { return "" })
	if err != nil || c.Address != "127.0.0.1:8080" || c.DatabaseURL != "" {
		t.Fatalf("unexpected defaults: %#v %v", c, err)
	}
	for _, input := range []map[string]string{
		{"PORT": "abc"}, {"PORT": "0"}, {"PORT": "65536"}, {"APP_ENV": "production"},
		{"DATABASE_URL": "https://bad"}, {"DATABASE_URL": "postgres://"},
		{"APP_ENV": "unknown"},
	} {
		_, err := Load(func(k string) string { return input[k] })
		if err == nil {
			t.Fatalf("accepted invalid config: %v", input)
		}
	}
	c, err = Load(func(k string) string {
		return map[string]string{"HOST": "0.0.0.0", "PORT": "8081", "APP_ENV": "production", "DATABASE_URL": "postgres://user:secret@localhost/cafe"}[k]
	})
	if err != nil || c.Address != "0.0.0.0:8081" {
		t.Fatalf("valid config rejected: %v", err)
	}
}
