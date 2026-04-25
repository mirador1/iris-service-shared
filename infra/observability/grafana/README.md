# `infra/observability/grafana/` — Grafana provisioning and dashboards

Files here are auto-loaded by Grafana on startup so the UI at
<http://localhost:3001> is usable with zero clicks. No manual "Add data
source → fill form → save" dance every time `docker compose down -v` wipes
the volume.

## Sub-directories

| Directory                                | Purpose                                                                                                                                                           |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`provisioning/`](provisioning/)         | Data source definitions (Prometheus, Loki, Tempo, etc.) auto-registered on startup. Currently holds `datasources.yaml`.                                          |
| [`dashboards-lgtm/`](dashboards-lgtm/)   | Grafana dashboards in JSON + the `.yaml` provisioning manifest that tells Grafana which JSON files to auto-import and into which folder.                          |

## How auto-loading works

The LGTM container mounts:

```
/etc/grafana/provisioning/datasources/datasources.yaml
/etc/grafana/provisioning/dashboards/dashboard-*.yaml
/var/lib/grafana/dashboards/*.json
```

On each startup, Grafana:

1. Reads every `datasources.yaml` under `provisioning/datasources/` and
   registers the listed data sources. Re-registration is idempotent —
   changes to URLs, credentials, etc. take effect on container restart.
2. Reads every `dashboard-*.yaml` under `provisioning/dashboards/`. Each
   file declares a dashboard **provider** that points to a folder; Grafana
   scans that folder for `*.json` and imports/updates them.

This is a **one-way sync**: editing a dashboard in the Grafana UI creates
an in-memory copy, but the next container restart re-imports the original
JSON and overwrites it. To persist an edit, export the JSON from the UI
(Dashboard settings → JSON Model) and commit it here.

## Dashboards (LGTM variant)

See [`dashboards-lgtm/README.md`](dashboards-lgtm/README.md) for the
file-by-file content of that folder.

## When to edit

- **Change a datasource URL** → `provisioning/datasources.yaml` (e.g.
  swap local Prometheus for Grafana Cloud Prometheus endpoint).
- **Add a new dashboard** → drop the `.json` into `dashboards-lgtm/` and
  add a reference in `dashboard-*-lgtm.yaml` if it's a new provider.
- **Export a manual edit** → in Grafana UI → Dashboard settings → JSON
  Model → paste over the file here.

## Production note

The production Grafana is **Grafana Cloud** (SaaS), not this local stack.
These JSONs are useful as source-of-truth for dashboards you want to
publish there too — the structure is compatible, only data source names
may need adjustment.
