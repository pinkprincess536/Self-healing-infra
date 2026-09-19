# Project Context

Working notes on the current state of the self-healing infrastructure project — read this first when picking up work in a new session, instead of re-deriving state from scratch.

## What this project is

Following `SELF-HEALING-PROJECT-GUIDE.md` (combined from two source PDFs): build a system that detects an NGINX failure, raises an alert, automatically recovers it, and verifies the recovery. Full stack: Docker/Compose → Prometheus → Alertmanager → Ansible → Terraform/AWS EC2 → GitHub Actions CI/CD.

Daily progress is logged in `journal/day-0N.md` — each file follows the PDF's pattern: build goals (checkboxes), topics, interview questions (with full answers filled in as we go), a commands table (command + two-line why/what explanation), "what I achieved today," and "what broke / what I learned."

## Repo / Git state

- Remote: `https://github.com/pinkprincess536/Self-healing-infra.git`
- `main` currently holds Day 1 + Day 2 work (commit `e5bc0cf`). Day 3 is not yet merged into `main`.
- Feature branches, one per day: `feature/day1-nginx-baseline`, `feature/day2-bind-mounts-linux`, `feature/day3-prometheus` (current branch, in progress, uncommitted as of this note).
- Workflow: create a feature branch per day → do the work → fill in the journal → commit → push. No PRs opened yet (decided to push branches + `main` directly rather than go through PR review, per explicit instruction).
- Line-ending warnings (`LF will be replaced by CRLF`) appear on every commit — this is normal Windows/git behavior, not a bug, ignore it.

## Environment quirks (read before debugging "why did X fail")

- **Docker Desktop is not always running**, and has gone down mid-session more than once. Symptom: `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine`. Fix:
  ```powershell
  Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
  $max=60; $i=0
  while ($i -lt $max) {
    docker info > $null 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Output "READY"; break }
    Start-Sleep -Seconds 5; $i++
  }
  ```
  Always run `docker compose ps -a` first when something seems broken — rule out "Docker isn't running" before assuming a config bug.
- **Port 8080 on the host is already occupied** by two other local processes (found via `Get-NetTCPConnection -LocalPort 8080`). This is why NGINX is published on **8083**, not 8080/8083 as the guide's generic example suggests. Don't "fix" this back to 8080.
- Shell is **PowerShell on Windows**. Use `curl.exe` explicitly — bare `curl` hits PowerShell's `Invoke-WebRequest` alias and behaves differently (no `-i`, different flags). Command chaining uses `;`, not `&&`. Use `Start-Sleep -Seconds N` instead of `sleep N`.
- PowerShell's `2>&1` redirection combined with git/docker CLI's normal stderr progress output frequently makes **successful** commands look like errors in captured output (`NativeCommandError`, non-zero exit code) even though the underlying operation succeeded. Always verify with a follow-up state check (`git status`, `docker compose ps -a`, an API query) rather than trusting the reported exit code alone.
- JSON parsing via `ConvertFrom-Json` on `curl.exe` output works well for querying Prometheus's HTTP API (`/api/v1/query`, `/api/v1/targets`, `/api/v1/rules`, `/api/v1/alerts`) — this has been the standard way of proving state throughout Day 3 instead of relying on the web UI.

## Current stack (`docker-compose.yml`)

| Service | Image | Purpose | Port |
|---|---|---|---|
| `nginx` | built from `./app` (`nginx:1.27-alpine` base) | The service being monitored/healed. Endpoints: `/health` (custom, plain "ok"), `/stub_status` (built-in NGINX module, feeds the exporter), `/` (static page). | 8083→80 |
| `tester` | `curlimages/curl:8.10.1` | Sleeps forever (`entrypoint: sleep infinity`); exists only to prove container-to-container DNS/networking via `docker exec tester curl http://nginx/health`. No production role, keep it around for future networking checks. | — |
| `nginx-exporter` | `nginx/nginx-prometheus-exporter:1.3.0` | Scrapes NGINX's `/stub_status` and re-exposes it in Prometheus text format (`nginx_up`, `nginx_http_requests_total`, etc). Prometheus cannot read NGINX's native stub_status format directly — this is the required translation layer. | 9113 |
| `prometheus` | `prom/prometheus:v2.55.1` | Scrapes itself + `nginx-exporter` every 15s (`scrape_interval: 15s`, `evaluation_interval: 15s`). Loads `alert_rules.yml`. **No Alertmanager wired up yet** — that's Day 4. | 9090 |

Key files and what they do:
- `app/Dockerfile` — `FROM nginx:1.27-alpine`, `WORKDIR`, `COPY` static content + config, `RUN nginx -t` (config validation at build time), `CMD`.
- `app/nginx.conf` — bind-mounted (not baked in) so it can be edited live and reloaded with `docker exec nginx nginx -s reload`, no rebuild needed. Defines `/health` and `/stub_status`.
- `app/html/index.html` — trivial static page for the `/` route.
- `monitoring/prometheus/prometheus.yml` — scrape config. Two jobs: `prometheus` (self-scrape, baseline sanity target) and `nginx` (points at `nginx-exporter:9113`, resolved via Compose's internal DNS).
- `monitoring/prometheus/alert_rules.yml` — see "Critical technical finding" below, this file was corrected mid-Day-3.

## Critical technical finding from the Day 3 detection experiment

**`up{job="nginx"}` is not the same thing as "is NGINX healthy."**

`up` is Prometheus's own built-in metric meaning "could I successfully scrape this target." The target for the `nginx` job is `nginx-exporter:9113` — so `up{job="nginx"}` only reflects whether the **exporter container** is reachable. It has nothing to do with whether NGINX itself, behind the exporter, is actually running.

We proved this directly: after `docker kill nginx`, the exporter container was still alive and Prometheus could still scrape it fine, so `up{job="nginx"}` stayed at `1` indefinitely — NGINX was down for 35+ minutes and the original alert rule (written against `up{job="nginx"} == 0`) never even entered `pending` state. Confirmed via `GET /api/v1/rules`, which showed `"state": "inactive"` the whole time.

The metric that actually reflects NGINX's own health is **`nginx_up`**, a gauge published by the exporter itself, representing whether the exporter's *own scrape of NGINX's `/stub_status`* succeeded. That one correctly dropped to `0` immediately after the kill (confirmed via `curl localhost:9113/metrics`).

**Fix applied:** `alert_rules.yml` now has two rules:
- `NginxDown`: `expr: nginx_up == 0`, `for: 2m`, `severity: critical` — the real service-failure signal, this is what recovery automation should key off in Day 4.
- `NginxExporterDown`: `expr: up{job="nginx"} == 0`, `for: 2m`, `severity: warning` — secondary rule that catches the *other* failure mode (exporter itself dies, so NGINX's health becomes unknown/unobservable, which is a different problem than NGINX being down).

This distinction is also explicitly listed in the interview bank ("What is a target? What is a metric? What does `up == 0` mean?") — now backed by a concrete, reproduced example rather than just the definition.

## End-to-end detection experiment — confirmed working (Day 3)

Full cycle proven via Prometheus's HTTP API (not just the UI):

1. **Healthy baseline:** `nginx_up 1`, `up{job="nginx"} = 1`, `GET /api/v1/alerts` → empty.
2. **Break:** `docker kill nginx` (SIGKILL, container shows `Exited (137)`).
3. **Detect (metric):** `nginx_up` on the exporter dropped to `0` within seconds. `up{job="nginx"}` stayed `1` (see finding above — this is expected, not a bug).
4. **Detect (alert):** After reloading Prometheus's config (`docker kill --signal=HUP prometheus`) to apply the corrected rule, `NginxDown` rule state went `inactive → pending` (condition true, waiting out `for: 2m`) → **`firing`** after ~2 minutes. Confirmed via both `/api/v1/rules` and `/api/v1/alerts`.
5. **Recover:** `docker start nginx`. Confirmed `nginx_up` back to `1` and `curl http://localhost:8083/health` returned `200 ok`.
6. **Verify/resolve:** Within ~20s of recovery, rule state returned to `inactive` and `/api/v1/alerts` went back to empty — the alert *resolved*, not just stopped firing silently.

This satisfies the Day 3 goal "test it with a controlled failure" and the detailed guide's Day 3.3 "Detection Experiment" phase goals in full.

## Day-by-day status

- **Day 1 — done, committed.** Repo structure, NGINX baseline with `/health`, Dockerfile (FROM/WORKDIR/COPY/RUN/CMD), first Compose stack, verified via curl/logs/exec, feature branch + clean commit. All 6 interview questions answered in `journal/day-01.md`.
- **Day 2 — done, committed.** Bind mount for `nginx.conf` (live reload via `nginx -s reload`, no rebuild), `tester` service proving container-to-container DNS networking, Linux/Docker diagnostics practiced (`ps aux`, `netstat -tuln`, `docker stats`), full Failure Lab cycle (hypothesis written first → `docker kill` → evidence collected via `docker inspect`/`docker logs` *before* fixing → manual `docker start` recovery → verified via real `/health` curl, not just container status). All 5 interview questions answered in `journal/day-02.md`.
- **Day 3 — build complete, verification complete, journal write-up and commit still pending.**
  - Built: `nginx-exporter` + `prometheus` services, `prometheus.yml` scrape config, `alert_rules.yml`.
  - Hit and fixed a real config bug: initial `prometheus.yml` had an invalid `alerting.alertmanager` key (should be `alertmanagers`, and shouldn't exist yet at all — Alertmanager isn't built until Day 4). Prometheus refused to start (`Exited (2)`) until the block was removed. Good real example for "what does Prometheus config-loading failure look like."
  - Hit and fixed the `up` vs `nginx_up` issue described above — this was the main learning moment of the day.
  - Ran the full detection experiment end-to-end successfully (see above).
  - **Remaining for Day 3:** fill in `journal/day-03.md`'s commands table, "what I achieved," "what I learned/broke" section (should foreground the `up` vs `nginx_up` finding), and the 6 interview question answers (`What does Prometheus do? Who exposes metrics? What is a target? What does UP mean? Scrape interval vs alert 'for'?` etc). Then `git add`, commit, push `feature/day3-prometheus`.

## Not started yet

- **Day 4:** Alertmanager service + config, webhook receiver (something that logs incoming alert payloads), Ansible recovery playbook (restart NGINX → wait → check port → check `/health` → assert), security basics (`.env`, `.gitignore`, no hardcoded secrets — not needed yet since nothing sensitive has been introduced).
- **Day 5:** Terraform + AWS EC2 provisioning, IAM role/instance profile instead of static credentials, GitHub Actions CI/CD (lint → test → build, conditional Docker build).
- **Day 6/7:** full integration demo (healthy → break → detect → recover → verify, three practice runs), README + architecture diagram, incident notes, final checklist review.
- No secrets exist in this repo yet. `.env`/`.gitignore` secret-handling becomes relevant starting Day 4 (webhook auth token) and Day 5 (AWS credentials) — flag this explicitly when we get there rather than hardcoding anything.

## Quick reference — useful verification commands

```powershell
# Is Docker even running?
docker info

# What's actually up?
docker compose ps -a

# Exporter's raw metrics
curl.exe -s http://localhost:9113/metrics | Select-String "nginx_up|nginx_http_requests_total"

# Prometheus: are both targets healthy?
curl.exe -s "http://localhost:9090/api/v1/targets" | ConvertFrom-Json | Select-Object -ExpandProperty data | Select-Object -ExpandProperty activeTargets | Select-Object -ExpandProperty labels

# Prometheus: run the actual up query
curl.exe -s "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22nginx%22%7D" | ConvertFrom-Json | ConvertTo-Json -Depth 5

# Prometheus: alert rule states (inactive / pending / firing)
curl.exe -s "http://localhost:9090/api/v1/rules" | ConvertFrom-Json | Select-Object -ExpandProperty data | Select-Object -ExpandProperty groups | Select-Object -ExpandProperty rules | Select-Object name,state

# Prometheus: currently firing alerts
curl.exe -s "http://localhost:9090/api/v1/alerts" | ConvertFrom-Json | Select-Object -ExpandProperty data

# Reload Prometheus config after editing prometheus.yml or alert_rules.yml (no restart needed)
docker kill --signal=HUP prometheus

# The Failure Lab pattern used every time: hypothesis → break → evidence → fix → verify
docker kill nginx            # break
docker inspect nginx --format "ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}}"  # evidence
docker start nginx           # fix
curl.exe -s -i http://localhost:8083/health   # verify (not just "Up" status)
```
