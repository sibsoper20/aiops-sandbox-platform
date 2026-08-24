# ADR 0001: Kubernetes reference platform

- Status: Accepted
- Date: 2026-08-25

## Decision

Use a self-managed, single-node k3s cluster as the first SOFTCON 2027 demonstration platform.

## Rationale

The design continues the Cost-Savvy SRE theme, keeps the demo portable through Kubernetes and OpenTelemetry interfaces, and avoids requiring a commercial AIOps platform.

## Consequences

This is a demonstration environment, not a production high-availability design. Capacity will be measured during implementation. Workloads can be resized or moved to additional nodes if a measured constraint requires it.
