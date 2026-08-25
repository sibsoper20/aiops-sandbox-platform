# Demonstration application validation

- Tester: Jesse Jadraque
- Host: UM780 XTX (`pop-os`)
- Branch: `softcon-2027`

## Increment A — Application foundation

| Check | Result | Evidence |
|---|---|---|
| Go formatting passes | Pass | `gofmt` reported no files requiring changes. |
| Unit and handler tests pass | Pass | Race-enabled tests passed in 1.019s with 46.6% statement coverage. |
| Go vet passes | Pass | `go vet ./...` completed without findings. |
| Health endpoint works | Pass | Returned `{"status":"ok"}`. |
| Readiness endpoint works | Pass | Returned ready with memory storage during source validation. |
| Order creation and listing work | Pass | Created and returned the SOFTCON Coffee validation order. |
| Prometheus metrics are exposed | Pass | Request, error, order, database, and duration metrics were returned. |
| Structured JSON request logs are emitted | Pass | Logs include request ID, method, path, status, duration, and storage. |
| Non-root container image builds | Pass | GitHub Actions container job completed successfully in 38 seconds. |
| GitHub Actions workflow passes | Pass | Test and container jobs both passed for commit `bc24639`. |

## Evidence

Source verification report: `/tmp/softcon-aiops-demo-api-source-20260825-234601.log`

Dependency integrity: `go mod verify` passed. Dependency metadata was committed as `bc24639`.

## Decision

Increment A accepted: Yes

The public image was published to GHCR with tags `softcon-2027` and `sha-bc24639`. Kubernetes uses the immutable commit tag `sha-bc24639`.

## Increment B — Kubernetes deployment

Not started.

## Increment C — Traffic and telemetry

Not started.
