# DAY 6 — Full Integration + Recovery Validation

Date: 2026-09-20

> Restart is an action. Recovery is a verified outcome.

## Scope decision

The detailed project guide treats CI/CD as Day 5.3. CI/CD was started separately and then intentionally postponed. Day 6 therefore focuses on the core integration loop: healthy → break → detect → alert → recover → verify → resolve.

## Daily build goals

- [x] Run the full system end to end.
- [x] Establish a clean healthy baseline before failure.
- [x] Simulate a controlled NGINX process/container failure.
- [x] Observe `nginx_up` change from 1 to 0.
- [x] Observe `NginxDown` move through inactive → pending → firing.
- [x] Verify Alertmanager routes the alert to the authenticated webhook.
- [x] Verify the webhook invokes Ansible.
- [x] Verify NGINX process, port and `/health` after recovery.
- [x] Verify `nginx_up` returns to 1 and the alert resolves.
- [x] Save timestamped evidence automatically.
- [x] Guarantee cleanup restores NGINX and `restart: unless-stopped`.
- [ ] Safely simulate CPU, memory and disk pressure (postponed; no alert rules exist for these yet).
- [ ] Complete GitHub Actions CI/CD (postponed Day 5.3 work).

## What we built

Two repeatable demo scripts:

- `scripts/run-recovery-demo.ps1` — runs the demo locally from Windows PowerShell.
- `scripts/run-recovery-demo.sh` — runs the same demo on Linux/EC2.

Both scripts:

1. Refuse to break NGINX unless the starting state is healthy.
2. Create a timestamped evidence log in `journal/evidence/`.
3. Record the original restart policy.
4. Disable Docker automatic restart for the experiment.
5. Kill NGINX deliberately.
6. Poll Prometheus metrics and rule state.
7. Wait for Alertmanager → webhook → Ansible recovery.
8. Verify health and alert resolution.
9. Require webhook logs proving firing, recovery and resolved events.
10. Always restore `unless-stopped` and start NGINX if necessary.

## Successful test evidence

Evidence file:

```text
journal/evidence/day6-20260920T174834Z.log
```

Observed timeline:

```text
Healthy baseline:
nginx_up=1, NginxDown=inactive, Prometheus alerts=0, Alertmanager alerts=0

Controlled failure:
nginx_running=false, health=down

t=  0s nginx_up=1 alert=inactive running=false health=down
t= 10s nginx_up=0 alert=pending  running=false health=down
t=100s nginx_up=0 alert=pending  running=false health=down
t=110s nginx_up=0 alert=firing   running=false health=down
t=120s nginx_up=0 alert=firing   running=true  health=ok

Resolution:
t=  0s nginx_up=0 alert=firing   Prometheus alerts=1 Alertmanager alerts=1 health=ok
t= 10s nginx_up=1 alert=firing   Prometheus alerts=1 Alertmanager alerts=1 health=ok
t= 20s nginx_up=1 alert=inactive Prometheus alerts=0 Alertmanager alerts=0 health=ok
```

Webhook evidence:

```text
alert received: status=firing alerts=['NginxDown']
running recovery: ansible-playbook -i /ansible/inventory.ini /ansible/restart_nginx.yml
recovery succeeded and passed validation
alert received: status=resolved alerts=['NginxDown']
alert resolved — no recovery needed
```

Final result:

```text
PASS
nginx_up 1 → 0 → 1
alert inactive → pending → firing → inactive
NGINX health → ok
restart policy → unless-stopped
active alerts → none
```

## Test cases

| ID | Test | Expected result | Actual result |
|---|---|---|---|
| D6-01 | Healthy baseline | NGINX healthy, `nginx_up=1`, no alerts | PASS |
| D6-02 | Hard-kill NGINX | Container exits 137 and health fails | PASS |
| D6-03 | Metric detection | `nginx_up` changes to 0 | PASS |
| D6-04 | Alert lifecycle | inactive → pending → firing | PASS |
| D6-05 | Routed recovery | Alertmanager calls authenticated webhook | PASS |
| D6-06 | Ansible recovery | NGINX container restarts | PASS |
| D6-07 | Deep validation | process running, port open, `/health` 200 `ok` | PASS |
| D6-08 | Monitoring feedback | `nginx_up=1`, alert inactive, alert counts zero | PASS |
| D6-09 | Resolved event | webhook logs resolved and does not restart again | PASS |
| D6-10 | Cleanup after script error | policy restored and NGINX started/healthy | PASS during the first failed script run |

## Commands I actually learned / used

| # | Command | Why / what it does |
|---|---|---|
| 1 | `docker compose ps -a` | Shows both running and stopped containers. Used to confirm the complete baseline and failure state. |
| 2 | `curl.exe -fsS http://127.0.0.1:8083/health` | Checks the real NGINX application response from Windows. `-f` fails on HTTP errors and `-sS` hides progress but keeps errors. |
| 3 | `docker inspect -f "{{.HostConfig.RestartPolicy.Name}}" nginx` | Reads the current NGINX restart policy before changing it. |
| 4 | `docker update --restart=no nginx` | Temporarily prevents Docker from hiding the experiment by restarting NGINX itself. |
| 5 | `docker kill nginx` | Introduces the controlled hard failure using SIGKILL. |
| 6 | Prometheus `/api/v1/query?query=nginx_up` | Reads the service-health metric and proves it changed from 1 to 0 and back to 1. |
| 7 | Prometheus `/api/v1/rules` | Reads `NginxDown` state and proves inactive → pending → firing → inactive. |
| 8 | Prometheus `/api/v1/alerts` | Counts active Prometheus alerts before, during and after recovery. |
| 9 | Alertmanager `/api/v2/alerts` | Proves Alertmanager held the active alert and later removed it. |
| 10 | `docker logs recovery-webhook --since <timestamp>` | Captures only webhook messages from the current demo run. |
| 11 | `powershell -File scripts/run-recovery-demo.ps1` | Runs the safe Windows integration demo and saves evidence. |
| 12 | `sudo bash scripts/run-recovery-demo.sh` | Linux/EC2 equivalent of the repeatable demo. |
| 13 | `bash -n scripts/run-recovery-demo.sh` | Checks Bash syntax without executing the destructive demo. |
| 14 | PowerShell parser `ParseFile(...)` | Checks PowerShell syntax without running the demo. |
| 15 | `docker update --restart=unless-stopped nginx` | Restores normal Docker protection after the controlled failure. |

## What broke and how it was diagnosed

### Script attempt 1 — expected curl failure became a PowerShell error

Immediately after killing NGINX, curl correctly failed because the service was down. PowerShell's `$ErrorActionPreference = "Stop"` converted curl's stderr into a terminating error before the script could record `health=down`.

Fix: `Test-NginxHealth` now catches the expected curl failure and returns `$false`. The cleanup block still ran successfully, proving the fail-safe behavior.

### Script attempt 2 — Docker logs use stderr

The integration flow passed, but PowerShell stopped while collecting webhook logs because `docker logs` writes container logs to stderr even when the command succeeds.

Fix: `Get-WebhookLogs` temporarily treats those lines as normal output and converts them to strings. Both scripts also wait up to 60 seconds for the resolved webhook notification because it may arrive after Prometheus and Alertmanager active-alert lists become empty.

### Cleanup policy observation

One run began with the old `no` restart policy left from manual testing, so restoring the original value preserved the wrong project setting. Both scripts now always restore the required `unless-stopped` value. The local container was corrected and verified healthy.

## Interview questions

### Why test before building an image?

Tests are faster and explain failures more clearly. If syntax, configuration or behavior is wrong, building and publishing an image only packages the problem and wastes time.

### When should a Docker build run?

Build when the Dockerfile, files copied into the image, dependencies or relevant Compose build settings change. Documentation-only changes do not need an image build.

### What is the difference between a GitHub Actions job and step?

A job gets its own runner and can run in parallel with other jobs. A step is one command/action inside a job and shares that job's workspace with the other steps.

### What does `needs` do in GitHub Actions?

`needs` creates an order between jobs. For example, a Docker build can require validation and tests to pass first.

### What does `${{ }}` mean?

It is GitHub Actions expression syntax. It reads contexts and values such as the current branch, secrets, outputs or previous job results before a step runs.

### CPU is high—what evidence should I collect?

First prove the symptom and find the owner: `uptime`, `top`, `ps`, and `docker stats`. Record which process/container uses CPU, how long it lasted, logs at that time and whether users experienced slow responses. Do not restart before collecting evidence.

### Disk is high—how do I find the source?

Use `df -h` to identify the full filesystem, then `du` to find large directories and files. Check Docker images/volumes/logs with `docker system df`, but do not run destructive cleanup until you know what is safe to remove.

## Short demo story

> I began with a healthy baseline: NGINX responded, `nginx_up` was 1 and no alerts existed. I disabled Docker's automatic restart so it could not hide the test, then killed NGINX. The health request failed, `nginx_up` became 0, and `NginxDown` moved from pending to firing. Alertmanager routed the alert with a Bearer token to the webhook. The webhook applied safety guards and ran Ansible. Ansible restarted NGINX and verified the container, port and `/health`. Prometheus then observed `nginx_up=1`, the alert resolved, and the webhook ignored the resolved event. Finally, the script restored `restart: unless-stopped` and saved timestamped evidence.

## Current recovery scope

The system currently performs one automated recovery action: restart the existing NGINX container. It handles a stopped, killed or temporarily unresponsive NGINX process while Docker, the host and the monitoring/recovery chain remain healthy.

It does not currently recreate a deleted container, repair invalid configuration, recover Docker/EC2 itself, repair networking, or remediate CPU/memory/disk pressure. See `CONCLUSION-PART-1.md` for the full recovery-scope matrix.

## What is next?

1. Run the Linux script on EC2 if another cloud demo is required.
2. Complete or formally postpone Day 5.3 CI/CD.
3. Add production hardening: Gunicorn, container healthchecks, resource limits and log rotation.
4. Finish the main README, architecture diagram and incident runbook.
5. Destroy the AWS lab after evidence is saved to stop charges.
