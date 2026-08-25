# Logging validation

- Date: 2026-08-25
- Tester: Jesse Jadraque
- Host: UM780 XTX (`pop-os`)
- Branch: `softcon-2027`

## Increment A — Loki storage

| Check | Result | Evidence |
|---|---|---|
| Loki monolithic workload is available | Not run | |
| Loki gateway is available | Not run | |
| Loki persistent volume is Bound | Not run | |
| Loki readiness endpoint succeeds | Not run | |
| Synthetic log push succeeds | Not run | |
| Synthetic LogQL query returns the log | Not run | |

## Decision

Increment A accepted: No

## Increment B — Kubernetes log collection

Not started.

## Increment C — Grafana log exploration

Not started.
