# SOFTCON 2027 AIOps Demo

A self-managed AIOps demonstration that runs on Kubernetes and uses Grafana telemetry plus a local AI model to produce evidence-backed incident investigations.

## Project status

The original 2025 Docker Compose proof of concept is preserved on the `legacy-poc-2025` branch. New Kubernetes work is developed on `softcon-2027`. The default `main` branch remains unchanged until the Kubernetes foundation is validated.

## Target architecture

- Single-node k3s initially
- `demo`, `observability`, `aiops`, and `storage` namespaces
- Grafana, Loki, Mimir, Alloy, and optional Tempo
- Containerized local model behind an OpenAI-compatible API
- Instrumented order application with controlled fault injection
- Human-triggered, evidence-backed investigation workflow

## First increment

This branch currently establishes:

1. Project organization and architecture decisions
2. Kubernetes namespaces
3. A disposable test workload, Service, and ingress
4. k3s installation and validation guidance

Stateful observability, business services, and model inference are intentionally excluded until the Kubernetes foundation is proven.

## Repository layout

- `docs/` — architecture, decisions, and runbooks
- `platform/` — k3s, namespaces, ingress, and storage
- `observability/` — telemetry platform configuration
- `applications/` — custom demo and AIOps services
- `model-serving/` — local inference deployment
- `tests/` — validation and evaluation
- `scripts/` — repeatable operations

## Validate the foundation

See [platform/k3s/README.md](platform/k3s/README.md).
