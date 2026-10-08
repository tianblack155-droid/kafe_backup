package main

import (
	"context"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strconv"
	"testing"
	"time"
)

func TestRunRealtimeEnvironmentRoutingAndShutdown(t *testing.T) {
	for _, origins := range []string{"", "http://localhost:3000"} {
		t.Run(origins, func(t *testing.T) {
			// Startup without DB cannot consume unrelated tests' outbox events.
			probe, err := net.Listen("tcp", "127.0.0.1:0")
			if err != nil {
				t.Fatal(err)
			}
			port := probe.Addr().(*net.TCPAddr).Port
			probe.Close()
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			done := make(chan error, 1)
			go func() {
				done <- run(ctx, func(k string) string {
					switch k {
					case "PORT":
						return strconv.Itoa(port)
					case "REALTIME_ORIGINS":
						return origins
					}
					return ""
				}, slog.New(slog.NewTextHandler(io.Discard, nil)))
			}()
			client := &http.Client{Timeout: time.Second}
			base := "http://127.0.0.1:" + strconv.Itoa(port)
			deadline := time.Now().Add(2 * time.Second)
			for {
				res, err := client.Get(base + "/health")
				if err == nil {
					io.Copy(io.Discard, res.Body)
					res.Body.Close()
					break
				}
				if time.Now().After(deadline) {
					t.Fatal(err)
				}
				time.Sleep(10 * time.Millisecond)
			}
			res, err := client.Get(base + "/api/v1/realtime")
			if err != nil {
				t.Fatal(err)
			}
			io.Copy(io.Discard, res.Body)
			res.Body.Close()
			want := 404
			if origins != "" {
				want = 403
			}
			if res.StatusCode != want {
				t.Errorf("realtime routing: got %d want %d", res.StatusCode, want)
			}
			cancel()
			select {
			case err := <-done:
				if err != nil {
					t.Fatal(err)
				}
			case <-time.After(3 * time.Second):
				t.Fatal("startup worker shutdown stuck")
			}
		})
	}
}
