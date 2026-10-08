package commerce

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// orderIDs is an internal test isolation seam, nil for the production worker.
// It never comes from HTTP or environment configuration.
type outboxStore struct {
	db       *pgxpool.Pool
	orderIDs []string
}

// dispatchBatch locks only committed pending rows. Publication means local hub
// enqueue, NOT receipt by a browser. Commit failure can duplicate invalidations;
// crash after commit can miss them. Ready/reconnect and periodic REST resync are
// mandatory. Event rows are preserved, including on queue overflow/disconnect.
func (s *outboxStore) dispatchBatch(ctx context.Context, rt *Realtime, limit int) (int, error) {
	ctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(context.Background())
	rows, err := tx.Query(ctx, `select id,order_id,order_version,event_type from tkm.outbox_events
 where published_at is null and ($1::uuid[] is null or order_id=any($1::uuid[]))
 order by created_at,id limit $2 for update skip locked`, s.orderIDs, boundedInt(limit, 100))
	if err != nil {
		return 0, err
	}
	var events []Invalidation
	for rows.Next() {
		event := Invalidation{Type: "order.changed"}
		if err = rows.Scan(&event.EventID, &event.OrderID, &event.Version, &event.EventType); err != nil {
			rows.Close()
			return 0, err
		}
		events = append(events, event)
	}
	rows.Close()
	if err = rows.Err(); err != nil {
		return 0, err
	}
	for _, event := range events {
		if ctx.Err() != nil {
			return 0, ctx.Err()
		}
		rt.dispatch(event)
		if _, err = tx.Exec(ctx, `update tkm.outbox_events set published_at=clock_timestamp() where id=$1`, event.EventID); err != nil {
			return 0, err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return 0, err
	}
	return len(events), nil
}

// Start starts at most one dispatcher and binds all sockets to ctx's lifetime.
// A disabled endpoint does not consume outbox events. Close must run before the
// API pool is closed, even if the HTTP listener exits with an error.
func (rt *Realtime) Start(ctx context.Context, logger *slog.Logger) error {
	rt.mu.Lock()
	defer rt.mu.Unlock()
	if rt.closed || rt.started {
		return errors.New("realtime already started or closed")
	}
	rt.started = true
	if logger == nil {
		logger = slog.Default()
	}
	rt.wg.Add(1)
	go func() {
		defer rt.wg.Done()
		stop := context.AfterFunc(ctx, rt.cancel)
		defer stop()
		if len(rt.origins) == 0 || rt.store == nil || rt.store.db == nil {
			<-rt.ctx.Done()
			return
		}
		tick := time.NewTicker(rt.cfg.PollInterval)
		defer tick.Stop()
		for {
			if rt.ctx.Err() != nil {
				return
			}
			_, err := rt.store.dispatchBatch(rt.ctx, rt, rt.cfg.BatchSize)
			if err != nil && rt.ctx.Err() == nil {
				logger.Warn("realtime outbox dispatch failed")
			}
			select {
			case <-rt.ctx.Done():
				return
			case <-tick.C:
			}
		}
	}()
	return nil
}
