# Self-Healing Infrastructure

A learning project that builds the classic detection → recovery loop from scratch: when NGINX goes down, the system notices, restarts it, and — critically — proves it is healthy again, without a human touching anything.

```text
NGINX failure
  → nginx-exporter reports nginx_up = 0
  → Prometheus waits 2 minutes and fires NginxDown
  → Alertmanager routes an authenticated webhook
  → webhook applies restart-loop guards and runs Ansible
  → Ansible restarts NGINX and validates process, port, and /health
  → nginx_up returns to 1 and the alert resolves
```

![Uploading self_healing_architecture_expanded.png…]()


> **Restart is an action. Recovery is a verified outcome.**

## Stack

| Layer | Tools |
|---|---|
| Service | NGINX in Docker, with `/health` and `/stub_status` |
| Packaging | Docker + Compose |
| Metrics | nginx-prometheus-exporter → Prometheus |
| Alerting | Prometheus rules → Alertmanager |
| Recovery | Flask webhook + Ansible playbook |
| Infrastructure | Terraform + AWS EC2 (IAM, SSM) |
| Config management | Ansible |

## Architecture

```text
Operator ──TCP 8083──> NGINX :8083

Prometheus ──scrape──> nginx-exporter :9113 ──scrape──> NGINX /stub_status
    │
    │ evaluates alert rules (nginx_up == 0 for 2m)
    ▼
Alertmanager ──Bearer token──> recovery-webhook :5000 ──> Ansible ──> docker restart nginx
                                                                     → process → port → /health
```

| Service | Purpose | Exposure |
|---|---|---|
| `nginx` | Demo service with `/health` and `/stub_status` | Host port 8083 |
| `tester` | Internal DNS/curl checks | Compose network only |
| `nginx-exporter` | Translates NGINX status into Prometheus metrics | Loopback 9113 |
| `prometheus` | Scrapes metrics and evaluates alerts | Loopback 9090 |
| `alertmanager` | Groups and routes alerts to recovery | Loopback 9093 |
| `recovery-webhook` | Authenticates alerts and runs Ansible | Compose port 5000 only |

## How it works

1. **NGINX** serves a demo page plus `/health` and `/stub_status`.
2. **nginx-exporter** reads `/stub_status` and re-exposes it in Prometheus format. NGINX does not speak Prometheus; the exporter is the translation layer.
3. **Prometheus** scrapes the exporter every 15s and evaluates two rules:
   - `NginxDown` — `nginx_up == 0` for `2m` (critical). This is the recovery signal: NGINX itself is unreachable.
   - `NginxExporterDown` — `up{job="nginx"} == 0` for `2m` (warning). The exporter is gone; NGINX health is unknown, so it is **not** routed to recovery.
4. **Alertmanager** receives firing alerts and routes only `NginxDown` to the recovery webhook, with a Bearer token read from a mounted file.
5. The **webhook** enforces guards (Bearer token, `status == firing`, alert name `NginxDown`, 60s cooldown, max 3 attempts / 10min, timeout) so it cannot restart-loop forever.
6. **Ansible** restarts the container, then verifies in three levels:
   - **Level 1** — container process is running
   - **Level 2** — port 80 accepts connections
   - **Level 3** — `/health` returns HTTP 200 `ok`
7. `nginx_up` returns to 1 and the alert resolves; the webhook logs and ignores the `resolved` event.

The key metric distinction learned the hard way:

- `nginx_up == 0` → NGINX is unavailable (the recovery signal).
- `up{job="nginx"} == 0` → the exporter is unavailable (NGINX health is unobservable).

## Repository layout

```text
app/                          NGINX Dockerfile, config, static page
monitoring/
  prometheus/                 prometheus.yml + alert_rules.yml
  alertmanager/               alertmanager.yml (routing + Bearer auth)
recovery/
  webhook/                    Flask app that runs Ansible
  ansible/                    restart_nginx.yml + inventory
infrastructure/
  terraform/                  VPC, subnet, SG, IAM role, EC2
  ansible/                    bootstrap-ec2.sh + configure_ec2.yml
scripts/                      repeatable recovery demo (Windows + Linux)
journal/                      day-by-day build journal and evidence
```

## Run it locally

Prerequisites: Docker Desktop and Docker Compose.

```powershell
# create the webhook token (gitignored)
New-Item -ItemType Directory -Force secrets | Out-Null
$token = [guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")
Set-Content -NoNewline secrets/webhook_token $token

docker compose up -d --build
curl.exe -i http://localhost:8083/health
```

Trigger the full loop safely with the repeatable demo script:

```powershell
powershell -File scripts/run-recovery-demo.ps1
```

The script refuses to break NGINX unless it starts healthy, saves timestamped evidence to `journal/evidence/`, and always restores `restart: unless-stopped`.

## Run it on AWS EC2

See [`infrastructure/terraform/README.md`](infrastructure/terraform/README.md) for the full workflow. In short:

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and set your `/32` operator CIDR.
2. `terraform init`, `validate`, `test`, then review `terraform plan`.
3. `terraform apply`, then connect over SSM and run `bootstrap-ec2.sh`, which runs the Ansible playbook.

Terraform creates a locked-down lab: a dedicated VPC, no inbound SSH (SSM only), monitoring ports bound to loopback, an EC2 IAM role limited to `AmazonSSMManagedInstanceCore`, IMDSv2 required, and an encrypted gp3 root volume.

## Security model

- The webhook token is generated locally, mounted from a gitignored file, and never committed.
- `/recover` requires a Bearer token, a `firing` status, and the `NginxDown` alert name.
- Alertmanager's `repeat_interval`, webhook cooldown, attempt window, and timeout prevent restart loops.
- Monitoring ports bind to loopback and are reached via SSM port forwarding.
- The Docker socket mount is a **deliberate lab limitation** — it gives the webhook root-level host control and is not a production security boundary.

## Recovery scope

Today the system performs exactly one verified action: restart the existing NGINX container after a process-level failure on an otherwise healthy host. It does not recreate deleted containers, repair bad config, heal Docker/EC2 itself, or remediate CPU/memory/disk pressure. See [`CONCLUSION-PART-1.md`](CONCLUSION-PART-1.md) for the full scope matrix.

## Build journal

A day-by-day record of what was built, what broke, and what was learned: [`journal/README.md`](journal/README.md).
