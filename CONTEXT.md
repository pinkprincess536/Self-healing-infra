# Self-Healing Infrastructure — Project Context

Read this file first when resuming the project. It records the architecture, current implementation, important decisions, reproduced failures, verification evidence, environment quirks, and next work.

## Goal and recovery loop

Build one observable, protected, repeatable loop:

```text
NGINX failure
  → nginx-exporter changes nginx_up from 1 to 0
  → Prometheus evaluates NginxDown
  → alert is pending for 2 minutes
  → Prometheus sends firing alert to Alertmanager
  → Alertmanager groups/routes it to the authenticated webhook
  → webhook applies restart-loop guards and invokes Ansible
  → Ansible restarts NGINX
  → process, port, and /health are validated
  → nginx_up returns to 1
  → Prometheus resolves the alert
  → Alertmanager sends a resolved event
  → webhook logs it and does not restart again
```

Project guide: `SELF-HEALING-PROJECT-GUIDE.md`. Daily notes: `journal/day-01.md` through `journal/day-07.md`.

## Git state

- Remote: `https://github.com/pinkprincess536/Self-healing-infra.git`
- Current branch: `feature/day4-alertmanager-ansible`
- `main` and `origin/main` contain completed Day 1–3 work at commit `f85f96c`.
- Day 4 is implemented and verified locally but is not committed/pushed yet.
- Day branches: `feature/day1-nginx-baseline`, `feature/day2-bind-mounts-linux`, `feature/day3-prometheus`, `feature/day4-alertmanager-ansible`.
- The working tree also contains user-authored journal edits/images. Do not discard or overwrite them; review and stage intentionally.

## Windows environment notes

- OS/shell: Windows PowerShell.
- Use `curl.exe`, not bare `curl`, to avoid PowerShell's `Invoke-WebRequest` alias.
- Use `;` for command sequencing and `Start-Sleep -Seconds N` for waits.
- Docker Desktop sometimes stops. Symptom: Docker API pipe error or services exiting with code 255. Start it with:

```powershell
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
while ($true) {
  docker info > $null 2>&1
  if ($LASTEXITCODE -eq 0) { break }
  Start-Sleep -Seconds 5
}
```

- After Docker returns, run `docker compose up -d` and verify with `docker compose ps -a`.
- Host port 8080 is already occupied. NGINX intentionally uses host port **8083** mapped to container port 80.
- Docker/git normally write progress to stderr. PowerShell may display `NativeCommandError` even when the operation succeeded; verify actual state rather than trusting that wrapper message alone.
- LF→CRLF Git warnings are expected on Windows.

## Current Compose stack

| Service | Image/build | Purpose | Host access |
|---|---|---|---|
| `nginx` | custom image based on `nginx:1.27-alpine` | Service being monitored and recovered; serves `/`, `/health`, `/stub_status` | `localhost:8083` → container `80` |
| `tester` | `curlimages/curl:8.10.1` | Internal DNS/network tests | none |
| `nginx-exporter` | `nginx/nginx-prometheus-exporter:1.3.0` | Converts NGINX stub status to Prometheus metrics | `localhost:9113` |
| `prometheus` | `prom/prometheus:v2.55.1` | Scrapes metrics, evaluates alert rules, sends alerts to Alertmanager | `localhost:9090` |
| `alertmanager` | `prom/alertmanager:v0.27.0` | Groups, routes, deduplicates, repeats, and resolves alerts | `localhost:9093` |
| `recovery-webhook` | custom Python/Flask + Ansible image | Authenticates recovery requests, applies safety guards, invokes Ansible | internal port 5000 only |

## Important files

### Service
- `app/Dockerfile`: builds the static NGINX service and validates config with `nginx -t`.
- `app/nginx.conf`: bind-mounted read-only; defines `/health` and `/stub_status`.
- `app/html/index.html`: demo page.

### Monitoring
- `monitoring/prometheus/prometheus.yml`: 15-second scrape/evaluation intervals; scrapes Prometheus and `nginx-exporter:9113`; sends alerts to `alertmanager:9093` using the required plural `alertmanagers` key.
- `monitoring/prometheus/alert_rules.yml`:
  - `NginxDown`: `nginx_up == 0` for 2m, critical, triggers recovery.
  - `NginxExporterDown`: `up{job="nginx"} == 0` for 2m, warning, does not trigger blind recovery.
- `monitoring/alertmanager/alertmanager.yml`: groups by `alertname`; 10s group wait, 30s group interval, 5m repeat interval; routes only `NginxDown` to the recovery receiver; uses Bearer credentials from a mounted token file; sends resolved events.

### Recovery
- `recovery/webhook/app.py`: Flask webhook with `/healthz`, `/status`, and protected `/recover` endpoints. It logs alert names/status, ignores resolved alerts, rate-limits recovery, executes Ansible with a timeout, and reports verified success/failure.
- `recovery/webhook/Dockerfile`: Python 3.12 Alpine plus pinned `ansible-core==2.17.6`, Docker CLI, and pinned Flask dependencies.
- `recovery/ansible/inventory.ini`: local lab inventory. Ansible runs locally inside the webhook container.
- `recovery/ansible/restart_nginx.yml`: restarts NGINX, waits, verifies container state, verifies port 80, verifies `/health` returns 200 with `ok`, and asserts success.
- `secrets/webhook_token`: generated 43-character local token; ignored and untracked.
- `secrets/webhook_token.example`: safe committed template.
- `.gitignore`: excludes secret files, `.env`, PEMs, Terraform state/variables, and Python caches while allowing secret examples.

## Security and safety model

- `/recover` requires a Bearer token. No token returns HTTP 401 and does not run Ansible.
- Alertmanager and the webhook read the same mounted token file; the token is not committed or written into Compose/config.
- Only `NginxDown` is allowed to invoke recovery. Exporter failure means observability is lost and should not cause a guessed NGINX restart.
- Alertmanager limits notification repeats to five minutes.
- Webhook guard defaults:
  - cooldown: 60 seconds between runs;
  - circuit breaker: at most 3 attempts in 600 seconds;
  - playbook timeout: 120 seconds.
- Resolved events are logged and ignored.
- The Docker socket gives the webhook powerful daemon access (effectively root-level Docker control). This is acceptable only for this isolated local lab. Day 5 should replace it with narrowly scoped SSH/SSM/IAM access on EC2.
- Flask's development server is suitable for this learning lab, not production. A production deployment should use a WSGI server and additional network controls.

## Critical metric lesson

`up{job="nginx"}` does **not** mean NGINX is healthy. It means Prometheus could scrape the configured target, which is the exporter. The exporter may be alive while NGINX is dead, so this metric can remain 1 during an NGINX outage.

`nginx_up` is the exporter's own gauge describing whether its last scrape of NGINX succeeded. Therefore:

- `nginx_up == 0` → NGINX unavailable → recovery candidate.
- `up{job="nginx"} == 0` → exporter unavailable → NGINX health unknown, observability incident.

This was discovered empirically on Day 3 when the original rule stayed inactive for more than 35 minutes while NGINX was down. Splitting it into two alerts fixed the design.

## Validation levels

A successful restart command is not recovery proof:

1. **Process/container:** `docker inspect` says the NGINX container is running.
2. **Port:** Ansible `wait_for` proves port 80 accepts a connection.
3. **Application:** Ansible `uri` proves `/health` returns HTTP 200; assertion verifies response contains `ok`.
4. **Monitoring feedback:** `nginx_up` returns to 1.
5. **Alert lifecycle:** Prometheus rule becomes inactive, Alertmanager has no active alert, and the webhook receives `status=resolved`.

## Verified Day 4 automatic demo

Configuration checks passed:

```text
promtool check config: SUCCESS; 1 rule file; 2 rules
promtool check rules: SUCCESS; 2 rules
amtool check-config: SUCCESS; 2 receivers
ansible-playbook --syntax-check: passed
Prometheus active Alertmanager: http://alertmanager:9093/api/v2/alerts
Alertmanager /-/ready: OK
Webhook /healthz: status=ok
Secret: ignored and not tracked
```

Manual playbook test passed all seven tasks with `failed=0`, including process, port, HTTP, and final assertion.

Automatic run evidence:

```text
BASELINE health=ok firingAlerts=0 webhookAttempts=0
BREAK: docker kill nginx
t=10s  nginx_up=1 rule=inactive nginxRunning=false webhookAttempts=0
t=20s  nginx_up=0 rule=inactive nginxRunning=false webhookAttempts=0
t=40s  nginx_up=0 rule=pending  nginxRunning=false webhookAttempts=0
t=140s nginx_up=0 rule=pending  nginxRunning=false webhookAttempts=0
t=150s nginx_up=1 rule=firing   nginxRunning=true  webhookAttempts=1
AUTOMATIC RECOVERY OBSERVED
FINAL health=ok HTTP=200 NginxDown=inactive prometheusAlerts=0 alertmanagerAlerts=0
```

Webhook log evidence:

```text
alert received: status=firing alerts=['NginxDown']
running recovery: ansible-playbook -i /ansible/inventory.ini /ansible/restart_nginx.yml
recovery succeeded and passed validation
alert received: status=resolved alerts=['NginxDown']
alert resolved — no recovery needed
```

Cooldown verification:

```text
first_status=200
immediate_second_status=429
{"reason":"cooldown active, 52s remaining","status":"suppressed"}
post-test health=ok HTTP=200
```

An earlier test labeled an invocation as an "immediate second call," but logs showed those two valid requests were about 147 seconds apart, longer than the configured 60-second cooldown. The corrected test above directly proves the guard works.

## Day status

- **Day 1 complete:** baseline service, Dockerfile, Compose, health endpoint, build/run/log/exec practice, interview answers and journal.
- **Day 2 complete:** bind mount, Compose DNS/networking, diagnostic ladder, controlled failure/evidence/manual recovery, interview answers and journal.
- **Day 3 complete:** exporter, Prometheus, targets, metrics, corrected alert rules, controlled detection lifecycle, interview answers and journal; committed to `main`.
- **Day 4 implementation and demo complete:** Alertmanager, authenticated webhook, Ansible recovery, validation, rate limits, resolved handling. Journal is updated. Remaining administrative step: final validation, then commit/push when requested.
- **Day 5 not started:** Terraform + AWS EC2, IAM, host configuration, then CI/CD according to the project guide.

## Quick verification commands

```powershell
# Runtime state
docker compose ps -a
curl.exe -s -i http://localhost:8083/health

# Config validation
docker exec prometheus promtool check config /etc/prometheus/prometheus.yml
docker exec prometheus promtool check rules /etc/prometheus/alert_rules.yml
docker exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml
docker exec recovery-webhook ansible-playbook --syntax-check -i /ansible/inventory.ini /ansible/restart_nginx.yml

# Connection and service readiness
curl.exe -s http://localhost:9090/api/v1/alertmanagers
curl.exe -s http://localhost:9093/-/ready
docker exec tester curl -s http://recovery-webhook:5000/healthz

# Metrics and alert states
curl.exe -s http://localhost:9113/metrics | Select-String "nginx_up|nginx_http_requests_total"
curl.exe -s http://localhost:9090/api/v1/rules | ConvertFrom-Json | ConvertTo-Json -Depth 8
curl.exe -s http://localhost:9090/api/v1/alerts
curl.exe -s http://localhost:9093/api/v2/alerts

# Recovery evidence and guard state
docker logs recovery-webhook --since 10m
docker exec tester curl -s http://recovery-webhook:5000/status

# Secret safety
git check-ignore -v secrets/webhook_token
git ls-files secrets/webhook_token
```

## Next work

1. Run final Day 4 validation once more after documentation edits.
2. Review/stage Day 4 files without losing user-authored journal changes.
3. Commit Day 4 on `feature/day4-alertmanager-ansible`, push it, merge/push `main` only when explicitly requested.
4. Begin Day 5 from updated `main`: Terraform AWS architecture, least-privilege IAM, EC2 provisioning, and repeatable host configuration.
