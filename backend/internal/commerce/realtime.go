package commerce

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/zDarkx1/TerasKayuManis/backend/internal/config"
)

// RealtimeConfig defaults are suitable for one active Go instance. API reuses
// the REST authority: Auth user lookup + profiles, or exact checkout capability.
// Zero limits select defaults; positive values may tighten, not relax, bounds.
type RealtimeConfig struct {
	API                                                                       *API
	Origins                                                                   []string
	AuthTimeout, RevalidateInterval, PingInterval, WriteTimeout, PollInterval time.Duration
	MaxConnections, MaxPerIdentity, QueueSize, BatchSize                      int
}

type Realtime struct {
	cfg     RealtimeConfig
	origins map[string]bool
	ctx     context.Context
	cancel  context.CancelFunc
	mu      sync.Mutex
	closed  bool
	started bool
	store   *outboxStore
	active  int
	peers   map[*realtimePeer]bool
	wg      sync.WaitGroup
}
type realtimePeer struct {
	sub      subscription
	identity string
	queue    chan Invalidation
	cancel   context.CancelFunc
}

// Invalidation is deliberately not an order snapshot. Consumers refetch REST.
type Invalidation struct {
	Type      string `json:"type"`
	EventID   string `json:"event_id"`
	OrderID   string `json:"order_id"`
	Version   int    `json:"version"`
	EventType string `json:"event_type"`
}
type subscription struct {
	Type        string `json:"type"`
	Channel     string `json:"channel"`
	OrderID     string `json:"order_id"`
	OrderToken  string `json:"order_token"`
	AccessToken string `json:"access_token"`
}

var uuidText = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

func boundedDuration(v, def time.Duration) time.Duration {
	if v <= 0 || v > def {
		return def
	}
	return v
}
func boundedInt(v, def int) int {
	if v <= 0 || v > def {
		return def
	}
	return v
}
func NewRealtime(cfg RealtimeConfig) (*Realtime, error) {
	if cfg.API != nil {
		api := *cfg.API
		if api.Client == nil {
			api.Client = http.DefaultClient
		}
		cfg.API = &api
	}
	origins := make(map[string]bool)
	for _, o := range cfg.Origins {
		parsed, err := config.ParseRealtimeOrigins(o)
		if err != nil || len(parsed) != 1 || parsed[0] != o {
			return nil, errors.New("invalid realtime origin")
		}
		origins[o] = true
	}
	cfg.AuthTimeout = boundedDuration(cfg.AuthTimeout, 5*time.Second)
	cfg.RevalidateInterval = boundedDuration(cfg.RevalidateInterval, 30*time.Second)
	cfg.PingInterval = boundedDuration(cfg.PingInterval, 20*time.Second)
	cfg.WriteTimeout = boundedDuration(cfg.WriteTimeout, 5*time.Second)
	cfg.MaxConnections = boundedInt(cfg.MaxConnections, 100)
	cfg.MaxPerIdentity = boundedInt(cfg.MaxPerIdentity, 5)
	cfg.QueueSize = boundedInt(cfg.QueueSize, 32)
	cfg.PollInterval = boundedDuration(cfg.PollInterval, 250*time.Millisecond)
	cfg.BatchSize = boundedInt(cfg.BatchSize, 100)
	ctx, cancel := context.WithCancel(context.Background())
	rt := &Realtime{cfg: cfg, origins: origins, ctx: ctx, cancel: cancel, peers: make(map[*realtimePeer]bool)}
	if cfg.API != nil {
		rt.store = &outboxStore{db: cfg.API.DB}
	}
	return rt, nil
}

// Handler mounts outside NewHandler's eight-second REST context. Existing
// NewHandler callers retain their API unchanged, with no implicit worker.
func (rt *Realtime) Handler(rest http.Handler) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("/api/v1/realtime", rt)
	mux.Handle("/", rest)
	return mux
}

// Close also waits for hijacked handlers, which http.Server.Shutdown cannot do.
func (rt *Realtime) Close() {
	rt.mu.Lock()
	rt.closed = true
	rt.cancel()
	rt.mu.Unlock()
	rt.wg.Wait()
}

func (rt *Realtime) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if len(rt.origins) == 0 {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if r.URL.RawQuery != "" || r.URL.ForceQuery {
		http.Error(w, "Query forbidden", 400)
		return
	}
	if len(r.Header.Values("Origin")) != 1 || !rt.origins[r.Header.Get("Origin")] {
		http.Error(w, "Origin forbidden", 403)
		return
	}
	if rt.cfg.API == nil || rt.cfg.API.DB == nil {
		http.Error(w, "Service unavailable", 503)
		return
	}
	rt.mu.Lock()
	if rt.closed || rt.active >= rt.cfg.MaxConnections {
		rt.mu.Unlock()
		http.Error(w, "Service unavailable", 503)
		return
	}
	rt.active++
	rt.wg.Add(1)
	rt.mu.Unlock()
	defer func() { rt.mu.Lock(); rt.active--; rt.mu.Unlock(); rt.wg.Done() }()
	// Exact origin was checked above: library defaults allow missing/same-host
	// origins and wildcard matching, neither of which is our security policy.
	c, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true, CompressionMode: websocket.CompressionDisabled})
	if err != nil {
		return
	}
	defer c.CloseNow()
	c.SetReadLimit(12 * 1024)
	ctx, cancel := context.WithCancel(rt.ctx)
	defer cancel()
	stopClose := context.AfterFunc(ctx, func() { _ = c.CloseNow() })
	defer stopClose()
	authCtx, authCancel := context.WithTimeout(ctx, rt.cfg.AuthTimeout)
	kind, body, err := c.Read(authCtx)
	var sub subscription
	if err == nil && kind == websocket.MessageText {
		d := json.NewDecoder(bytes.NewReader(body))
		d.DisallowUnknownFields()
		err = d.Decode(&sub)
		if err == nil && d.Decode(new(any)) != io.EOF {
			err = errors.New("extra JSON")
		}
	} else {
		err = errors.New("invalid frame")
	}
	var identity string
	var expiry time.Time
	if err == nil {
		identity, expiry, err = rt.authorize(authCtx, sub)
	}
	authCancel()
	if err != nil {
		return
	}
	// Validated UUIDs compare by value, independent of hexadecimal letter case.
	// Do this only after authorization of the original, strictly formatted ID.
	sub.OrderID = strings.ToLower(sub.OrderID)
	if !expiry.IsZero() {
		var expireCancel context.CancelFunc
		ctx, expireCancel = context.WithDeadline(ctx, expiry)
		defer expireCancel()
		stop := context.AfterFunc(ctx, cancel)
		defer stop()
	}
	p := &realtimePeer{sub: sub, identity: identity, queue: make(chan Invalidation, rt.cfg.QueueSize), cancel: cancel}
	rt.mu.Lock()
	count := 0
	for other := range rt.peers {
		if other.identity == identity {
			count++
		}
	}
	if rt.closed || count >= rt.cfg.MaxPerIdentity {
		rt.mu.Unlock()
		return
	}
	rt.peers[p] = true
	rt.mu.Unlock()
	defer func() { rt.mu.Lock(); delete(rt.peers, p); rt.mu.Unlock() }()
	// Register before ready, and use a single writer so ready precedes events.
	if err = rt.write(ctx, c, map[string]string{"type": "ready"}); err != nil {
		return
	}
	var tasks sync.WaitGroup
	tasks.Add(2)
	go func() { defer tasks.Done(); defer cancel(); rt.writeLoop(ctx, c, p) }()
	go func() { defer tasks.Done(); defer cancel(); rt.revalidate(ctx, p) }()
	// No additional application messages accepted. Read handles ping/pong.
	_, _, _ = c.Read(ctx)
	cancel()
	tasks.Wait()
}

func (rt *Realtime) write(ctx context.Context, c *websocket.Conn, v any) error {
	writeCtx, cancel := context.WithTimeout(ctx, rt.cfg.WriteTimeout)
	defer cancel()
	return wsjson.Write(writeCtx, c, v)
}
func (rt *Realtime) writeLoop(ctx context.Context, c *websocket.Conn, p *realtimePeer) {
	tick := time.NewTicker(rt.cfg.PingInterval)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case event := <-p.queue:
			if rt.write(ctx, c, event) != nil {
				return
			}
		case <-tick.C:
			pingCtx, cancel := context.WithTimeout(ctx, rt.cfg.WriteTimeout)
			err := c.Ping(pingCtx)
			cancel()
			if err != nil {
				return
			}
		}
	}
}
func (rt *Realtime) revalidate(ctx context.Context, p *realtimePeer) {
	tick := time.NewTicker(rt.cfg.RevalidateInterval)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			authCtx, cancel := context.WithTimeout(ctx, rt.cfg.AuthTimeout)
			id, _, err := rt.authorize(authCtx, p.sub)
			cancel()
			if err != nil || id != p.identity {
				return
			}
		}
	}
}
func (rt *Realtime) dispatch(event Invalidation) {
	rt.mu.Lock()
	defer rt.mu.Unlock()
	for p := range rt.peers {
		if p.sub.Channel != "cashier" && p.sub.OrderID != event.OrderID {
			continue
		}
		select {
		case p.queue <- event:
		default:
			p.cancel()
		}
	}
}

// JWT claims are only an additional expiry bound, never authentication. The
// entire original bearer must first pass Supabase Auth and the profile allowlist.
func tokenExpiry(token string) (time.Time, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 || len(token) > 8185 {
		return time.Time{}, errors.New("invalid token")
	}
	b, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return time.Time{}, errors.New("invalid token")
	}
	var claims struct {
		Exp int64 `json:"exp"`
	}
	if json.Unmarshal(b, &claims) != nil || claims.Exp <= 0 {
		return time.Time{}, errors.New("invalid expiry")
	}
	expiry := time.Unix(claims.Exp, 0)
	if !expiry.After(time.Now()) {
		return time.Time{}, errors.New("expired")
	}
	return expiry, nil
}
func (rt *Realtime) authorize(ctx context.Context, s subscription) (string, time.Time, error) {
	denied := errors.New("invalid subscription")
	if s.Type != "subscribe" {
		return "", time.Time{}, denied
	}
	r, _ := http.NewRequestWithContext(ctx, "GET", "http://internal/", nil)
	switch s.Channel {
	case "order":
		if !uuidText.MatchString(s.OrderID) || s.OrderToken == "" || s.AccessToken != "" {
			return "", time.Time{}, denied
		}
		r.SetPathValue("id", s.OrderID)
		r.Header.Set("X-Order-Token", s.OrderToken)
		if !rt.cfg.API.canReadOrder(r) {
			return "", time.Time{}, denied
		}
		return "order:" + strings.ToLower(s.OrderID), time.Time{}, nil
	case "cashier":
		if s.OrderID != "" || s.OrderToken != "" || s.AccessToken == "" {
			return "", time.Time{}, denied
		}
		expiry, err := tokenExpiry(s.AccessToken)
		if err != nil {
			return "", time.Time{}, denied
		}
		r.Header.Set("Authorization", "Bearer "+s.AccessToken)
		id, err := rt.cfg.API.staff(r)
		if err != nil {
			return "", time.Time{}, denied
		}
		if !expiry.After(time.Now()) {
			return "", time.Time{}, denied
		}
		return "staff:" + id, expiry, nil
	default:
		return "", time.Time{}, denied
	}
}
