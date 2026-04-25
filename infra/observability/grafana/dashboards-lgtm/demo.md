# demo.json — Grafana dashboard (LGTM stack)

Loaded automatically by Grafana via `dashboard-demo-lgtm.yaml` when the LGTM observability
stack is running (`./run.sh obs`). Open Grafana at http://localhost:3001.

> **LGTM vs Prometheus-only**
> This dashboard targets the **OTel SDK metric naming convention** where histograms and timers
> are exported in milliseconds (`_milliseconds_`). The equivalent dashboard at
> `dashboards/demo.json` uses the Micrometer → Prometheus direct-scrape convention (`_seconds_`).
> Both dashboards show the same business signals — only the unit suffix differs.

---

## Panels

| Panel | Query | What it shows |
|---|---|---|
| HTTP requests rate | `sum(rate(http_server_requests_milliseconds_count[1m]))` | Total request throughput across all endpoints, aggregated per minute |
| Customer created count | `customer_created_count_total` | Cumulative counter incremented by `CustomerService` on each successful `POST /customers` |
| Customer create latency p95 | `histogram_quantile(0.95, sum(rate(customer_create_duration_milliseconds_bucket[5m])) by (le))` | 95th-percentile latency for the customer creation path (DB write + Kafka publish) |
| Customer aggregate latency p95 | `histogram_quantile(0.95, sum(rate(customer_aggregate_duration_milliseconds_bucket[5m])) by (le))` | 95th-percentile latency for `GET /customers/{id}/enrich` (parallel sub-tasks via virtual threads) |
| Recent customer buffer size | `customer_recent_buffer_size` | Current size of the in-memory `RecentCustomerBuffer` |

---

## Metrics origin

| Metric | Registered by |
|---|---|
| `http_server_requests_milliseconds_*` | Spring Boot auto-configuration (OTel bridge) |
| `customer_created_count_total` | `CustomerService` — `Counter` in `ObservabilityConfig` |
| `customer_create_duration_milliseconds_*` | `CustomerService` — `Timer` in `ObservabilityConfig` |
| `customer_aggregate_duration_milliseconds_*` | `AggregationService` — `Timer` in `ObservabilityConfig` |
| `customer_recent_buffer_size` | `RecentCustomerBuffer` — `Gauge` in `ObservabilityConfig` |

---

## Provisioning path

```
deploy/compose/observability.yml
  └── grafana/otel-lgtm container
        └── /otel-lgtm/demo.json          ← this file (mounted from dashboards-lgtm/)
        └── /otel-lgtm/dashboard-demo-lgtm.yaml  ← provisioning config
```
