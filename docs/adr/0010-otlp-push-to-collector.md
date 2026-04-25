# ADR-0010: OpenTelemetry OTLP push to a Collector (not Prometheus scrape)

- **Status**: Accepted
- **Date**: 2026-04-16

## Context

The backend emits three telemetry signals: **metrics**, **traces**, and
**logs**. Each signal has at least two viable delivery models:

| Model                     | Metrics            | Traces              | Logs              |
| ------------------------- | ------------------ | ------------------- | ----------------- |
| **Scrape (Prometheus)**   | `/actuator/prometheus` pulled by Prometheus | N/A (no pull model) | N/A |
| **Push (OTLP over HTTP)** | OTLP exporter → Collector | OTLP exporter → Collector | OpenTelemetry Logback appender → Collector |
| **Push (OTLP over gRPC)** | same, binary wire    | same                | same              |

Historically we started with Prometheus scrape for metrics + Jaeger
push for traces + Loki push for logs, which meant three exporters,
three sets of endpoints, and three separate credential scopes in
production (Grafana Cloud requires `Basic <token>` auth on every
ingest path).

## Decision

**All three signals push via OTLP/HTTP to an OpenTelemetry Collector.**
The app does not expose a `/actuator/prometheus` endpoint for
production scrape.

- Local dev: OTLP endpoint defaults to the LGTM container at
  `http://localhost:4318` (no auth).
- Production (GKE): OTLP endpoint points to the in-cluster OTel
  Collector DaemonSet
  (`opentelemetry-kube-stack` Helm chart, namespace
  `opentelemetry-operator-system`). The Collector holds the Grafana
  Cloud credentials (`grafana-cloud-auth` K8s Secret) and forwards to
  Grafana Cloud.

Spring Boot wires the exporters via `management.opentelemetry.*` in
`src/main/resources/application.yml`. The Authorization header is
injected into the app only in production via the K8s Deployment env
var `MANAGEMENT_TRACING_EXPORT_OTLP_HEADERS_AUTHORIZATION` — Spring
Boot's relaxed binding maps it to the `headers` map automatically. The
local LGTM path deliberately does NOT set an empty "Basic " header
(which would break ingest).

## Consequences

### Positive

- **One protocol, one endpoint, one credential.** The app has no idea
  whether the other side is LGTM, a local Collector, or Grafana Cloud
  — it just ships OTLP.
- **Credential isolation.** The app never sees Grafana Cloud tokens
  in local dev. Only the production Collector holds the secret, and
  only that Collector egresses to Grafana Cloud. The app's ServiceAccount
  has no IAM to reach the outside world.
- **Mirrors the Grafana Cloud recommended deployment.** Kube-stack
  Helm chart + app-side OTLP SDK is the documented happy path.
- **Switching backends is a Collector config change**, not an app
  restart. We can point the Collector at Tempo, Mimir, Loki, or
  Grafana Cloud without touching `application.yml`.

### Negative

- **No pull-based health check for metrics.** With scrape, Prometheus
  naturally detects "this target stopped responding" via its own
  liveness. With push, silence is ambiguous (collector down? app
  hung?). We mitigate with actuator `health` probes on `/actuator/health`
  (K8s readiness/liveness), independent of the metric path.
- **OTel Collector becomes a critical-path dependency.** If the
  Collector DaemonSet is broken, telemetry stops — but the app keeps
  serving traffic. The Collector has its own PDB to keep availability
  at 1 pod per node minimum.
- **Prometheus exemplars still work**, but they require both ends to
  speak the same protocol. Micrometer auto-configures exemplar
  sampling when `micrometer-tracing` is on the classpath and
  `tracing.sampling.probability > 0` — no extra bean needed.

### Neutral

- `/actuator/prometheus` is **disabled** in production (the endpoint
  is not in `management.endpoints.web.exposure.include`). Local dev
  keeps it exposed for ad-hoc `curl` inspection.
- Sampling is 100% locally (`tracing.sampling.probability: 1.0`) and
  10% in production via `OTEL_TRACES_SAMPLER_ARG=0.1` env override.

## Alternatives considered

### Alternative A — Prometheus scrape for metrics, OTLP for traces/logs

Rejected as the steady state (it was our v0). Means two separate
credential scopes, two ingest paths to Grafana Cloud, and a second
`ServiceMonitor`-style discovery mechanism. The uniformity gain of
all-OTLP outweighs the small "metrics also scrape-able" flexibility.

### Alternative B — OTLP/gRPC instead of OTLP/HTTP

Rejected: gRPC is marginally more efficient on the wire but requires
HTTP/2 end-to-end. Our GKE Ingress + Grafana Cloud path both prefer
HTTP/1.1 for simpler TLS termination. OTLP/HTTP protobuf is plenty
fast for our throughput (<1 k spans/min).

### Alternative C — App pushes directly to Grafana Cloud (no Collector)

Rejected: would embed the Grafana Cloud token in the app's K8s Secret,
which widens the blast radius (every app replica, every image build
log) vs the Collector-in-the-middle approach. Also loses the ability
to redact/reshape/route spans before egress.

## References

- `src/main/resources/application.yml` — `management.opentelemetry.*`
  block with the local-vs-prod auth comment.
- `src/main/resources/logback-spring.xml` — OpenTelemetry Logback
  appender wiring logs into the same OTLP pipeline.
- `docs/architecture/observability.md` / `docs/reference/technologies.md`
  — broader observability context.
- [OpenTelemetry Collector documentation](https://opentelemetry.io/docs/collector/).
