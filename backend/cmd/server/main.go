package main

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zDarkx1/TerasKayuManis/backend/internal/app"
	"github.com/zDarkx1/TerasKayuManis/backend/internal/commerce"
	"github.com/zDarkx1/TerasKayuManis/backend/internal/config"
	"github.com/zDarkx1/TerasKayuManis/backend/internal/httpapi"
)

func run(ctx context.Context, getenv func(string) string, logger *slog.Logger) error {
	cfg, err := config.Load(getenv)
	if err != nil {
		return err
	}
	var db httpapi.Pinger
	var businessPool *pgxpool.Pool
	if cfg.DatabaseURL != "" {
		poolCfg, err := pgxpool.ParseConfig(cfg.DatabaseURL)
		if err != nil {
			return errors.New("invalid database configuration")
		}
		poolCfg.MaxConns = 5
		poolCfg.MinConns = 0
		poolCfg.ConnConfig.ConnectTimeout = 2 * time.Second
		poolCfg.MaxConnLifetime = time.Hour
		poolCfg.MaxConnIdleTime = 5 * time.Minute
		pool, err := pgxpool.NewWithConfig(ctx, poolCfg)
		if err != nil {
			return errors.New("could not initialize database pool")
		}
		defer pool.Close()
		db = pool
		businessPool = pool
	} else {
		logger.Warn("DATABASE_URL not configured; /ready returns 503")
	}
	listener, err := net.Listen("tcp", cfg.Address)
	if err != nil {
		return errors.New("could not listen on configured address")
	}
	defer listener.Close()
	expiryCtx, stopExpiry := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() { defer close(done); commerce.RunExpiry(expiryCtx, businessPool, logger) }()
	defer func() { stopExpiry(); <-done }()
	authURL, authKey := getenv("SUPABASE_URL"), getenv("SUPABASE_ANON_KEY")
	realtime, err := commerce.NewRealtime(commerce.RealtimeConfig{
		API:     &commerce.API{DB: businessPool, AuthURL: authURL, AuthKey: authKey, Client: http.DefaultClient},
		Origins: cfg.RealtimeOrigins,
	})
	if err != nil {
		return err
	}
	if err = realtime.Start(ctx, logger); err != nil {
		realtime.Close()
		return err
	}
	// LIFO: stop sockets/dispatcher, then expiry, then pool. Also runs on listener
	// failure, not only signal cancellation; HTTP shutdown ignores hijacked sockets.
	defer realtime.Close()
	logger.Info("HTTP server started", "address", listener.Addr().String(), "environment", cfg.Environment)
	return app.Serve(ctx, listener, db, logger, realtime.Handler(commerce.NewHandler(businessPool, authURL, authKey)))
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx, os.Getenv, logger); err != nil {
		logger.Error("server stopped", "error", err.Error())
		os.Exit(1)
	}
}
