package main

import (
	"bytes"
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func testApplication() *application {
	return &application{
		store:   &memoryStore{},
		metrics: &appMetrics{},
		logger:  slog.New(slog.NewJSONHandler(io.Discard, nil)),
	}
}

func TestHealthAndReadiness(t *testing.T) {
	server := httptest.NewServer(testApplication().routes())
	defer server.Close()

	for _, path := range []string{"/healthz", "/readyz"} {
		response, err := http.Get(server.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		if response.StatusCode != http.StatusOK {
			t.Fatalf("%s returned %d", path, response.StatusCode)
		}
	}
}

func TestCreateAndListOrder(t *testing.T) {
	server := httptest.NewServer(testApplication().routes())
	defer server.Close()

	response, err := http.Post(server.URL+"/api/orders", "application/json",
		bytes.NewBufferString(`{"product":"Coffee","quantity":2}`))
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != http.StatusCreated {
		t.Fatalf("create returned %d", response.StatusCode)
	}

	response, err = http.Get(server.URL + "/api/orders")
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	if response.StatusCode != http.StatusOK || !strings.Contains(string(body), "Coffee") {
		t.Fatalf("unexpected list response: status=%d body=%s", response.StatusCode, body)
	}
}

func TestRejectsInvalidOrder(t *testing.T) {
	request := httptest.NewRequest(http.MethodPost, "/api/orders",
		bytes.NewBufferString(`{"product":"","quantity":0}`))
	recorder := httptest.NewRecorder()
	testApplication().routes().ServeHTTP(recorder, request)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", recorder.Code)
	}
}

func TestMemoryStoreLimit(t *testing.T) {
	store := &memoryStore{}
	_ = store.Create(context.Background(), order{ID: "one"})
	_ = store.Create(context.Background(), order{ID: "two"})
	values, err := store.List(context.Background(), 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(values) != 1 || values[0].ID != "two" {
		t.Fatalf("unexpected values: %#v", values)
	}
}

func TestMetrics(t *testing.T) {
	app := testApplication()
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	recorder := httptest.NewRecorder()
	app.routes().ServeHTTP(recorder, request)

	metricsRequest := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	metricsRecorder := httptest.NewRecorder()
	app.routes().ServeHTTP(metricsRecorder, metricsRequest)
	body := metricsRecorder.Body.String()
	if !strings.Contains(body, "demo_http_requests_total") ||
		!strings.Contains(body, "demo_http_request_duration_seconds_count") {
		t.Fatalf("metrics missing: %s", body)
	}
}
