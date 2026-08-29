package main

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

type order struct {
	ID        string    `json:"id"`
	Product   string    `json:"product"`
	Quantity  int       `json:"quantity"`
	CreatedAt time.Time `json:"created_at"`
}

type orderStore interface {
	Ready(context.Context) error
	Create(context.Context, order) error
	List(context.Context, int) ([]order, error)
	Close() error
	Mode() string
}

type memoryStore struct {
	mu     sync.RWMutex
	orders []order
}

func (s *memoryStore) Ready(context.Context) error { return nil }
func (s *memoryStore) Close() error                { return nil }
func (s *memoryStore) Mode() string                { return "memory" }

func (s *memoryStore) Create(_ context.Context, value order) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.orders = append([]order{value}, s.orders...)
	return nil
}

func (s *memoryStore) List(_ context.Context, limit int) ([]order, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if limit > len(s.orders) {
		limit = len(s.orders)
	}
	result := make([]order, limit)
	copy(result, s.orders[:limit])
	return result, nil
}

type postgresStore struct {
	db      *sql.DB
	metrics *appMetrics
}

func newPostgresStore(ctx context.Context, url string, metrics *appMetrics) (*postgresStore, error) {
	db, err := sql.Open("pgx", url)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(30 * time.Minute)

	store := &postgresStore{db: db, metrics: metrics}
	if err := store.Ready(ctx); err != nil {
		db.Close()
		return nil, err
	}
	_, err = db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS orders (
			id TEXT PRIMARY KEY,
			product TEXT NOT NULL,
			quantity INTEGER NOT NULL CHECK (quantity > 0),
			created_at TIMESTAMPTZ NOT NULL
		)`)
	if err != nil {
		db.Close()
		return nil, fmt.Errorf("create orders table: %w", err)
	}
	return store, nil
}

func (s *postgresStore) Ready(ctx context.Context) error {
	s.metrics.dbQueries.Add(1)
	if err := s.db.PingContext(ctx); err != nil {
		s.metrics.dbErrors.Add(1)
		return err
	}
	return nil
}

func (s *postgresStore) Create(ctx context.Context, value order) error {
	s.metrics.dbQueries.Add(1)
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO orders (id, product, quantity, created_at) VALUES ($1, $2, $3, $4)`,
		value.ID, value.Product, value.Quantity, value.CreatedAt)
	if err != nil {
		s.metrics.dbErrors.Add(1)
	}
	return err
}

func (s *postgresStore) List(ctx context.Context, limit int) ([]order, error) {
	s.metrics.dbQueries.Add(1)
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, product, quantity, created_at FROM orders ORDER BY created_at DESC LIMIT $1`,
		limit)
	if err != nil {
		s.metrics.dbErrors.Add(1)
		return nil, err
	}
	defer rows.Close()

	result := make([]order, 0, limit)
	for rows.Next() {
		var value order
		if err := rows.Scan(&value.ID, &value.Product, &value.Quantity, &value.CreatedAt); err != nil {
			s.metrics.dbErrors.Add(1)
			return nil, err
		}
		result = append(result, value)
	}
	return result, rows.Err()
}

func (s *postgresStore) Close() error { return s.db.Close() }
func (s *postgresStore) Mode() string { return "postgres" }

type appMetrics struct {
	requests       atomic.Uint64
	errors         atomic.Uint64
	ordersCreated  atomic.Uint64
	dbQueries      atomic.Uint64
	dbErrors       atomic.Uint64
	durationMicros atomic.Uint64
	incidentDelays atomic.Uint64
	incidentErrors atomic.Uint64
}

func (m *appMetrics) handler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	fmt.Fprintf(w, "# HELP demo_http_requests_total Total HTTP requests.\n")
	fmt.Fprintf(w, "# TYPE demo_http_requests_total counter\n")
	fmt.Fprintf(w, "demo_http_requests_total %d\n", m.requests.Load())
	fmt.Fprintf(w, "# HELP demo_http_errors_total Total HTTP responses with status 500 or greater.\n")
	fmt.Fprintf(w, "# TYPE demo_http_errors_total counter\n")
	fmt.Fprintf(w, "demo_http_errors_total %d\n", m.errors.Load())
	fmt.Fprintf(w, "# HELP demo_orders_created_total Total orders created.\n")
	fmt.Fprintf(w, "# TYPE demo_orders_created_total counter\n")
	fmt.Fprintf(w, "demo_orders_created_total %d\n", m.ordersCreated.Load())
	fmt.Fprintf(w, "# HELP demo_db_queries_total Total database operations.\n")
	fmt.Fprintf(w, "# TYPE demo_db_queries_total counter\n")
	fmt.Fprintf(w, "demo_db_queries_total %d\n", m.dbQueries.Load())
	fmt.Fprintf(w, "# HELP demo_db_query_errors_total Total failed database operations.\n")
	fmt.Fprintf(w, "# TYPE demo_db_query_errors_total counter\n")
	fmt.Fprintf(w, "demo_db_query_errors_total %d\n", m.dbErrors.Load())
	fmt.Fprintf(w, "# HELP demo_http_request_duration_seconds_sum Total HTTP request duration.\n")
	fmt.Fprintf(w, "# TYPE demo_http_request_duration_seconds summary\n")
	fmt.Fprintf(w, "demo_http_request_duration_seconds_sum %.6f\n", float64(m.durationMicros.Load())/1_000_000)
	fmt.Fprintf(w, "demo_http_request_duration_seconds_count %d\n", m.requests.Load())
	fmt.Fprintf(w, "# HELP demo_incident_delay_injections_total Total requests delayed by incident simulation.\n")
	fmt.Fprintf(w, "# TYPE demo_incident_delay_injections_total counter\n")
	fmt.Fprintf(w, "demo_incident_delay_injections_total %d\n", m.incidentDelays.Load())
	fmt.Fprintf(w, "# HELP demo_incident_error_injections_total Total HTTP errors injected by incident simulation.\n")
	fmt.Fprintf(w, "# TYPE demo_incident_error_injections_total counter\n")
	fmt.Fprintf(w, "demo_incident_error_injections_total %d\n", m.incidentErrors.Load())
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

type application struct {
	store          orderStore
	metrics        *appMetrics
	logger         *slog.Logger
	incident       incidentConfig
	incidentCursor atomic.Uint64
}

type incidentConfig struct {
	delay        time.Duration
	errorPercent uint64
}

func (a *application) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", a.health)
	mux.HandleFunc("GET /readyz", a.ready)
	mux.HandleFunc("GET /api/orders", a.listOrders)
	mux.HandleFunc("POST /api/orders", a.createOrder)
	mux.HandleFunc("GET /metrics", a.metrics.handler)
	return a.observe(a.injectIncident(mux))
}

func (a *application) injectIncident(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/api/") {
			next.ServeHTTP(w, r)
			return
		}
		if a.incident.delay > 0 {
			a.metrics.incidentDelays.Add(1)
			a.logger.Warn("incident delay injected", "path", r.URL.Path, "delay_ms", a.incident.delay.Milliseconds())
			timer := time.NewTimer(a.incident.delay)
			defer timer.Stop()
			select {
			case <-r.Context().Done():
				return
			case <-timer.C:
			}
		}
		if a.incident.errorPercent > 0 && a.incidentCursor.Add(1)%100 < a.incident.errorPercent {
			a.metrics.incidentErrors.Add(1)
			a.logger.Error("incident error injected", "path", r.URL.Path, "error_percent", a.incident.errorPercent)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "simulated incident"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (a *application) observe(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		writer := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		requestID := r.Header.Get("X-Request-ID")
		if requestID == "" {
			requestID = newID()
		}
		writer.Header().Set("X-Request-ID", requestID)
		next.ServeHTTP(writer, r)
		duration := time.Since(start)
		a.metrics.requests.Add(1)
		a.metrics.durationMicros.Add(uint64(duration.Microseconds()))
		if writer.status >= 500 {
			a.metrics.errors.Add(1)
		}
		a.logger.Info("request completed",
			"request_id", requestID,
			"method", r.Method,
			"path", r.URL.Path,
			"status", writer.status,
			"duration_ms", float64(duration.Microseconds())/1000,
			"storage", a.store.Mode())
	})
}

func (a *application) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (a *application) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := a.store.Ready(ctx); err != nil {
		a.logger.Error("readiness failed", "error", err, "storage", a.store.Mode())
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not_ready"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready", "storage": a.store.Mode()})
}

func (a *application) createOrder(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Product  string `json:"product"`
		Quantity int    `json:"quantity"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	input.Product = strings.TrimSpace(input.Product)
	if input.Product == "" || input.Quantity < 1 || input.Quantity > 100 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "product is required and quantity must be between 1 and 100"})
		return
	}
	value := order{ID: newID(), Product: input.Product, Quantity: input.Quantity, CreatedAt: time.Now().UTC()}
	if err := a.store.Create(r.Context(), value); err != nil {
		a.logger.Error("create order failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "could not create order"})
		return
	}
	a.metrics.ordersCreated.Add(1)
	writeJSON(w, http.StatusCreated, value)
}

func (a *application) listOrders(w http.ResponseWriter, r *http.Request) {
	limit := 20
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 100 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "limit must be between 1 and 100"})
			return
		}
		limit = parsed
	}
	values, err := a.store.List(r.Context(), limit)
	if err != nil {
		a.logger.Error("list orders failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "could not list orders"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"orders": values, "count": len(values)})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func newID() string {
	value := make([]byte, 12)
	if _, err := rand.Read(value); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(value)
}

func buildStore(ctx context.Context, metrics *appMetrics, logger *slog.Logger) (orderStore, error) {
	url := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if url == "" {
		logger.Warn("DATABASE_URL is empty; using in-memory storage")
		return &memoryStore{}, nil
	}
	store, err := newPostgresStore(ctx, url, metrics)
	if err != nil {
		return nil, fmt.Errorf("connect to PostgreSQL: %w", err)
	}
	return store, nil
}

func loadIncidentConfig() (incidentConfig, error) {
	config := incidentConfig{}
	if raw := strings.TrimSpace(os.Getenv("INCIDENT_DELAY_MS")); raw != "" {
		value, err := strconv.Atoi(raw)
		if err != nil || value < 0 || value > 10000 {
			return config, fmt.Errorf("INCIDENT_DELAY_MS must be between 0 and 10000")
		}
		config.delay = time.Duration(value) * time.Millisecond
	}
	if raw := strings.TrimSpace(os.Getenv("INCIDENT_ERROR_PERCENT")); raw != "" {
		value, err := strconv.Atoi(raw)
		if err != nil || value < 0 || value > 100 {
			return config, fmt.Errorf("INCIDENT_ERROR_PERCENT must be between 0 and 100")
		}
		config.errorPercent = uint64(value)
	}
	return config, nil
}

func run() error {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	metrics := &appMetrics{}
	incident, err := loadIncidentConfig()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	store, err := buildStore(ctx, metrics, logger)
	cancel()
	if err != nil {
		return err
	}
	defer store.Close()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	server := &http.Server{
		Addr:              ":" + port,
		Handler:           (&application{store: store, metrics: metrics, logger: logger, incident: incident}).routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	shutdown := make(chan os.Signal, 1)
	signal.Notify(shutdown, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-shutdown
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = server.Shutdown(ctx)
	}()

	logger.Info("demo API starting", "port", port, "storage", store.Mode(),
		"incident_delay_ms", incident.delay.Milliseconds(), "incident_error_percent", incident.errorPercent)
	err = server.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

func main() {
	if err := run(); err != nil {
		slog.Error("demo API stopped", "error", err)
		os.Exit(1)
	}
}
