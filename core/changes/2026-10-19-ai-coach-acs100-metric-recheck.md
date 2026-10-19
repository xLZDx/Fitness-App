# ACS-100 natural-metric recheck

Date: 2026-10-19  
Repository: `D:\Repo\Fitness_App_aicoach`  
Metric project: `fitness-app-korostelev`  
Target Cloud Run service: `aicoachadvice` / region `europe-west1`  
Execution: read-only Cloud Monitoring API GET authenticated by the configured `gcloud` credential. No AI callable was invoked and no production resource was changed.

## Query

Metric type: `run.googleapis.com/container/instance_count_with_readiness`  
Monitored resource: `cloud_run_revision`  
Filter: `resource.labels.service_name = "aicoachadvice" AND resource.labels.location = "europe-west1"`  
Metric labels returned: `readiness_status` (`HEALTHY`, `UNHEALTHY`, `UNKNOWN`).

The query used `GET /v3/projects/fitness-app-korostelev/timeSeries` with the filter above and an explicit start/end interval. A first attempt to use `gcloud monitoring time-series list` was rejected by the installed Cloud SDK with `Invalid choice: 'time-series'`; the read-only API GET was then used. The access token was kept in process memory and was not printed or recorded.

## Results

| Window (UTC) | Series / points | Result |
|---|---:|---|
| `2026-10-19T09:30:53Z` – `2026-10-19T09:47:53Z` | 0 / 0 | `NO_POINTS` |
| `2026-10-12T09:51:05Z` – `2026-10-19T09:48:05Z` | 3 / 132 | 44 points per readiness status |

The latest point in the seven-day result was `2026-10-16T11:32:00Z`, revision `aicoachadvice-00006-cay`; HEALTHY, UNHEALTHY and UNKNOWN each had value `0`. The descriptor reports a 60-second sample period and up to 120-second ingest delay. The 17-minute query ended three minutes before query execution, so its empty result is not explained by that documented ingest delay.

## Interpretation and ownership

- Freshness gate G2 remains BLOCKED. No point represents current readiness. Historical zero counts across the three labels are not evidence that the service is currently healthy or unhealthy.
- Continue with read-only observation of naturally reported points. Do not call `aiCoachAdvice`, create synthetic user traffic, deploy, or mutate the alert policy to force a sample.
- Codex owns the technical recheck during an active work session. GPT-PM owns product decisions. No persistent/background polling process or 24/7 on-call rotation is established by this query; the task roles do not imply either.

## Verification limits

The API request succeeded and returned the results above. No tests, project checks, builds, CI, migrations or production mutations were run. This observation is a point-in-time snapshot and must be refreshed before the ACS-100 deployment gate is reconsidered.

## Current-turn natural-metric recheck

On 2026-10-19, Codex repeated the same read-only Cloud Monitoring API query for the 24-hour interval `2026-10-18T17:44:35Z`–`2026-10-19T17:41:35Z` UTC, ending three minutes before the query to account for the documented ingest delay. The API returned HTTP 200 and zero matching `cloud_run_revision` time series for `service_name=aicoachadvice`, `location=europe-west1`, and `run.googleapis.com/container/instance_count_with_readiness`. No callable was invoked, no synthetic traffic was generated, and no policy/channel/resource was changed. This remains `NO_POINTS` / `OBSERVABILITY UNKNOWN`; the service is not inferred healthy or unhealthy, and freshness gate G2 remains BLOCKED. The bearer token was held in process memory and was not printed or recorded.

Exact query window and result were produced in this turn by a read-only GET to `projects/fitness-app-korostelev/timeSeries` using the in-session `gcloud` credential. The first PowerShell JSON inspection attempt returned an unexpected abbreviated body and was not used as evidence; a second request parsed the response with Python's standard-library JSON/HTTP client and independently reported `HTTP 200`, `series_count=0` for the same interval and filter.
