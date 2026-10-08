package main

import (
	"context"
	"io"
	"log/slog"
	"testing"
)

func TestRunRejectsInvalidConfig(t *testing.T) {
	err := run(context.Background(), func(k string) string {
		if k == "PORT" {
			return "invalid"
		}
		return ""
	}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err == nil {
		t.Fatal("expected config error")
	}
}
