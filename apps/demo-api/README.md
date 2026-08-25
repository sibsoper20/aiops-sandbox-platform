# Demo order API

This Go service is the customer-facing workload for the SOFTCON 2027 AIOps demonstration.

It is intentionally small enough to understand during a conference session, while still exposing realistic operational signals.

## API

| Method | Path | Purpose |
|---|---|---|
| GET | `/healthz` | Confirms that the process is alive |
| GET | `/readyz` | Confirms that the selected storage is reachable |
| GET | `/api/orders?limit=20` | Returns recent orders |
| POST | `/api/orders` | Creates an order |
| GET | `/metrics` | Exposes Prometheus-format metrics |

Example request:

```bash
curl -X POST \
  -H 'Content-Type: application/json' \
  --data '{"product":"SOFTCON Coffee","quantity":2}' \
  http://127.0.0.1:8080/api/orders
```

## Storage modes

When `DATABASE_URL` is defined, the service connects to PostgreSQL and creates its `orders` table automatically.

When it is empty, the service uses in-memory storage. This mode exists for local learning and source validation. Kubernetes will use PostgreSQL.

## Local validation

From the repository root:

```bash
bash scripts/19-verify-demo-api-source.sh
```

The script downloads Go dependencies, checks formatting, runs race-enabled tests and vet, starts the service, exercises the API, checks metrics, and verifies JSON logs.

## Signals

Metrics use the `demo_` prefix and cover requests, server errors, orders, database activity, and total request duration.

Logs are JSON and include request ID, method, path, response status, duration, and storage mode.

## Container

The image is built with Go 1.27.0 and runs on a distroless base as a non-root user. GitHub Actions publishes branch and commit tags to:

```text
ghcr.io/sibsoper20/aiops-sandbox-platform/demo-api
```
