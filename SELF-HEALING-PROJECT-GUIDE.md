# SELF-HEALING INFRASTRUCTURE — COMBINED GUIDE

> Build it once. Break it deliberately. Understand why it works.

This document combines two source guides in full:
1. **SELF-HEALING Infrastructure Project Guide** (11 pages) — the high-level day-by-day guide.
2. **SELF-HEALING INFRASTRUCTURE — Detailed Build + Instincts + Interview Guide** (26 pages) — the detailed phase-by-phase guide with instincts, commands, and reference material.

Stack: Prometheus + Alertmanager + Ansible + Docker + Linux + Terraform + AWS + CI/CD

---

# PART 1 — PROJECT GUIDE

## PROJECT OBJECTIVE

Build a system that detects a service failure, raises an alert, triggers automated recovery, and verifies that the service is healthy again.

**Core demo:** deliberately stop NGINX → Prometheus detects it → Alertmanager receives the alert → webhook triggers recovery → Ansible restarts NGINX → health is verified.

## CORE ARCHITECTURE

`GitHub → CI/CD → Docker/NGINX → Ubuntu VM or AWS EC2 → Prometheus → Alertmanager → Webhook → Ansible → Restart → Verify`

| Layer | Tools | Practice |
|---|---|---|
| Source control | Git, GitHub CLI | Branches, commits, PRs |
| Packaging | Docker, Compose | Images, containers, networking, mounts |
| Infrastructure | Terraform, EC2 | IaC, IAM, reproducibility |
| Configuration | Ansible | Repeatable setup and recovery |
| Observability | Prometheus, Alertmanager | Metrics, thresholds, alert flow |
| Delivery | GitHub Actions | Lint → test → build |

**SCOPE RULE:** Build the core system first. KMS and other extras are optional.

---

## HOW THE SYSTEM WORKS

Keep this page beside you while building. Your job is to understand every arrow.

1. **Service:** NGINX runs on a Linux host or inside Docker. Start simple.
2. **Monitoring:** Prometheus scrapes configured targets and evaluates metrics.
3. **Alerting:** Prometheus evaluates alert rules and sends firing alerts to Alertmanager.
4. **Routing:** Alertmanager routes the alert and can call a webhook.
5. **Recovery:** the recovery mechanism invokes Ansible to restart the failed service.
6. **Verification:** confirm the service is healthy again; a successful command is not enough.

### FAILURE LOOP

`Failure → Metric changes → Alert fires → Alertmanager → Webhook → Ansible → Restart → Metric recovers → Alert resolves`

### DESIGN QUESTIONS

- What exactly counts as service failure?
- Which metric represents that failure?
- How long should the condition remain true before alerting?
- How does Alertmanager reach the recovery endpoint?
- How does recovery authenticate to the host?
- How do you prevent repeated restart loops?
- How do you verify recovery?
- Where will logs exist when something fails?

---

## DAY 1 — Docker + NGINX + Compose

**Daily build goals**
- Create repo/project structure.
- Create simple application/NGINX endpoint.
- Write and understand Dockerfile.
- Build/run image; practice logs and exec.
- Create first Compose stack.
- Use a feature branch and clean commit.

**Topics to refer to**
- Dockerfile: FROM, WORKDIR, COPY, RUN, CMD
- Image vs container
- Layers
- Docker CLI
- Compose services
- Port mapping
- Git branching

**Interview questions**
- What happens between `docker build` and `docker run`?
- Why is an image different from a container?
- What does WORKDIR do?
- Why do Dockerfile instructions create layers?
- What does `8083:8080` mean?
- Why use Compose?

**Extra related topics — only if core work is stable**
- Docker networking
- Bind mounts
- Docker volumes
- Container healthchecks

**What I achieved today** — features, commands, experiments, screenshots, breakthroughs

**What I learned / what broke / what I want to remember**

---

## DAY 2 — Docker Deep Dive + Linux

**Daily build goals**
- Use a bind mount for NGINX configuration.
- Change config without rebuilding.
- Understand container-to-container communication.
- Practice Linux process/service commands.
- Investigate NGINX logs/status.
- Document what evidence each command gives you.

**Topics to refer to**
- Bind mounts vs volumes
- Docker bridge networking
- localhost inside containers
- systemctl
- journalctl
- ps / top / htop / uptime
- kill / pkill

**Interview questions**
- Container runs but app is unreachable: what do you check?
- NGINX is down: what do you check first?
- What does systemctl tell you?
- Where are service logs?
- Process kill vs service stop?

**Extra related topics — only if core work is stable**
- Docker healthchecks
- Linux signals
- systemd units
- Restart policies

**What I achieved today** — features, commands, experiments, screenshots, breakthroughs

**What I learned / what broke / what I want to remember**

---

## DAY 3 — Prometheus Monitoring

**Daily build goals**
- Run Prometheus with Compose.
- Configure targets.
- Confirm targets are reachable.
- Find useful service-health metrics.
- Write a first alert rule.
- Test it with a controlled failure.

**Topics to refer to**
- Prometheus architecture
- Scraping
- Targets
- Metrics
- PromQL basics
- Alert rules
- Evaluation intervals

**Interview questions**
- What does Prometheus do?
- Why is Prometheus commonly scrape-based?
- What is a target?
- What makes a useful alert?
- Why avoid alerts for tiny fluctuations?
- How would you detect NGINX unavailable?

**Extra related topics — only if core work is stable**
- Node Exporter
- cAdvisor
- Recording rules
- Alert duration
- Metric cardinality

**What I achieved today** — features, commands, experiments, screenshots, breakthroughs

**What I learned / what broke / what I want to remember**

---

## DAY 4 — Alertmanager + Ansible Recovery

**Daily build goals**
- Run Alertmanager.
- Connect Prometheus alerts to Alertmanager.
- Configure a webhook receiver.
- Create the recovery trigger.
- Write Ansible playbook to restart NGINX.
- Test recovery manually first.
- Verify service after recovery.

**Topics to refer to**
- Alertmanager routing
- Receivers
- Webhooks
- Ansible inventory
- Playbooks
- Modules/tasks
- Idempotence

**Interview questions**
- Why use Alertmanager?
- What is a webhook?
- How does Ansible know which machine to configure?
- Why is idempotence useful?
- How should automated recovery be limited?
- How do you verify recovery?

**Extra related topics — only if core work is stable**
- Ansible handlers
- Vault/secret handling
- Retries/timeouts
- Alert grouping/inhibition

**What I achieved today** — features, commands, experiments, screenshots, breakthroughs

**What I learned / what broke / what I want to remember**

---

## DAY 5 — Terraform + AWS EC2

**Daily build goals**
- Create AWS infrastructure with Terraform.
- Provision EC2 and required security/network configuration.
- Use IAM role instead of hard-coded credentials where appropriate.
- Use configuration management to set up the stack.
- Run the monitoring/recovery system on EC2.
- Test reproducibility by recreating a component.

**Topics to refer to**
- Terraform provider/resource
- Variables/outputs
- State
- init/plan/apply/destroy
- EC2
- Security Groups
- IAM roles

**Interview questions**
- What is Terraform state?
- Why is plan useful?
- Infrastructure creation vs configuration?
- Why use an IAM role on EC2?
- What network access is actually required?
- What should never be committed to Git?

**Extra related topics — only if core work is stable**
- Remote state
- Terraform modules
- SSM
- CloudWatch
- KMS

**What I achieved today** — features, commands, experiments, screenshots, breakthroughs

**What I learned / what broke / what I want to remember**

---

## DAY 6 — CI/CD + Full Failure Simulation

**Daily build goals**
- Create GitHub Actions: checkout → lint → test → Docker build.
- Use branches and pull requests.
- Make Docker build conditional on relevant changes where practical.
- Run end-to-end.
- Simulate service failure.
- Safely simulate CPU/memory/disk pressure in a controlled environment.
- Capture evidence of detection and recovery.

**Topics to refer to**
- Workflow/job/step
- needs
- if
- `${{ }}`
- Secrets
- Linux performance tools
- Prometheus + Alertmanager flow

**Interview questions**
- Why test before image build?
- When should Docker build run?
- Job vs step?
- How do Actions expressions work?
- CPU high: what evidence?
- Disk high: how find source?

**Extra related topics — only if core work is stable**
- Image caching
- Artifacts
- Deployment environments
- Resource limits
- Runbooks

**What I achieved today** — features, commands, experiments, screenshots, breakthroughs

**What I learned / what broke / what I want to remember**

---

## DAY 7 — Integration + Demo + Documentation

**Daily build goals**
- Run from a clean state.
- Demonstrate normal operation.
- Trigger controlled failure.
- Show Prometheus detection.
- Show Alertmanager routing.
- Show Ansible recovery.
- Verify health.
- Finish README, diagram and incident notes.
- Explain system without the guide.

**Topics to refer to**
- Incident response
- Observability
- Root cause vs symptom
- Runbooks
- Architecture documentation
- Least privilege
- Recovery verification

**Interview questions**
- Walk through architecture.
- Where can recovery fail?
- How prevent restart loops?
- What would you monitor in production?
- How secure the webhook?
- What changes with multiple replicas?
- How debug a false alert?

**Extra related topics — only if core work is stable**
- High availability
- Blue/green
- Canary
- SLO/SLI
- Distributed tracing

**What I achieved today** — features, commands, experiments, screenshots, breakthroughs

**What I learned / what broke / what I want to remember**

---

## INCIDENT PLAYBOOK

When the project breaks, do not immediately restart everything. Collect evidence first.

| Symptom | Evidence | Tools |
|---|---|---|
| NGINX down | Status, process, logs, port | systemctl, journalctl, ps, ss, curl |
| Container restarting | Exit code, logs, config, resources | docker ps/logs/inspect |
| CPU high | Process/container consuming CPU | uptime, top, htop, ps, docker stats |
| Memory high | Usage, process, OOM evidence | free, top, ps, dmesg/journalctl |
| Disk high | Filesystem, mount, largest dirs | df, du, lsblk, mount |
| Prometheus target down | Target state, endpoint, config | Prometheus UI, curl, logs |
| Alert not firing | Metric, rule, labels, evaluation | PromQL, rules UI, logs |
| Ansible fails | Inventory, connectivity, permissions, task output | ansible-playbook -v, systemctl, logs |

### INCIDENT METHOD

`Confirm → Collect evidence → Form hypothesis → Test → Fix → Verify → Document`

**INCIDENT NOTES** — What happened? Evidence? Root cause? Fix? Verification?

---

## FINAL PROJECT CHECKLIST

The project is complete when you can demonstrate the detection → recovery loop and explain the architecture.

**Core system**
- [ ] NGINX/service runs successfully.
- [ ] Dockerfile is reproducible.
- [ ] Docker Compose runs the supporting stack.
- [ ] Prometheus scrapes targets.
- [ ] A meaningful alert rule exists.
- [ ] Alertmanager receives the alert.
- [ ] Webhook reaches recovery.
- [ ] Ansible performs recovery.
- [ ] Health is verified after recovery.
- [ ] At least one controlled failure has been reproduced and recovered.

**Infrastructure + delivery**
- [ ] Terraform creates required AWS infrastructure.
- [ ] IAM permissions are understood and narrow.
- [ ] Configuration management is repeatable.
- [ ] Git branches/PR workflow was used.
- [ ] GitHub Actions runs lint → test → build.
- [ ] Docker build is appropriately conditional where required.
- [ ] Secrets are not hard-coded.

**Proof**
- [ ] README explains architecture.
- [ ] Architecture diagram is included.
- [ ] Failure/recovery evidence is saved.
- [ ] Incident runbook exists.
- [ ] I can explain every arrow.
- [ ] I can troubleshoot CPU, memory, disk and service failures.
- [ ] I can answer the interview questions without the guide.

**What I built**

**What I understand now**

**What I would improve next**

---

# PART 2 — DETAILED BUILD + INSTINCTS + INTERVIEW GUIDE

## THE CORE MENTAL MODEL

You are not building separate tools. You are building one failure/recovery loop: **service → observe → alert → route → recover → verify → resolve.**

### THE RULE FOR EVERY PHASE

- Build the thing.
- Run it.
- Break/test it when appropriate.
- Collect evidence.
- Explain WHY it exists.
- Write the commands you actually learned.
- Only then move on.

### FAILURE LAB

```
# Before breaking:
# What am I breaking?
# How will I break it?
# What should I see?
# How will I fix it?

# Safe examples:
docker stop nginx
systemctl stop nginx
```

---

## PROJECT MAP — 5.5 DAYS

| Day | Phases | End-of-day instinct |
|---|---|---|
| 1 | Baseline → Dockerfile → Compose/failure | I understand the service and container boundary. |
| 2 | Config → Linux diagnosis → Failure Lab | I investigate before restarting. |
| 3 | Prometheus → metrics → alerts | I connect symptoms to metrics. |
| 4 | Alertmanager → security → Ansible | I explain detection-to-recovery. |
| 5 | Terraform → EC2 config → CI/CD | I reproduce infrastructure and delivery. |
| 6 half | Integration → validation → demo | I explain and prove the whole loop. |

### DIAGNOSTIC LADDER

- Process/container? → `docker ps` / `systemctl status nginx`
- Port listening? → `ss -tuln`
- Responding? → `curl`
- Why? → `docker logs` / `journalctl`
- Resources? → `docker stats` / `top`

---

## DAY 1 | 1.1 — Baseline Service + Git

**Phase purpose:** Establish a known-good NGINX service before adding automation.

**Build goals**
- Create repo and feature branch.
- Run NGINX and verify it with curl.
- Record what 'healthy' means: response, process and port.
- Make a clean commit.

**Topics to refer to**
- Git / GitHub CLI
- Branching
- NGINX
- curl
- Healthy baseline

**Critical instinct checks — say the answer out loud**
- Can I explain exactly what service I am building?
- Can I explain what curl proves and what it does not prove?
- Can I predict what changes when NGINX dies?
- Why do we need a known-good baseline before monitoring?

**Extra related topics — do not let these derail the core build**
- Health endpoint
- Runbook basics
- Failure hypothesis

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 1 | 1.2 — Dockerfile + Image Mental Model

**Phase purpose:** Package the service reproducibly.

**Build goals**
- Write FROM, WORKDIR, COPY, RUN, CMD.
- Build and run the image.
- Use logs/exec/inspect.
- Understand image vs container and layers.

**Topics to refer to**
- Dockerfile instructions
- Layers
- docker build/run/logs/exec
- Port publishing

**Critical instinct checks — say the answer out loud**
- Why is each instruction here?
- What is inside an image vs a running container?
- Why do layers matter?
- What does `8080:80` mean?

**Extra related topics — do not let these derail the core build**
- Multi-stage builds
- .dockerignore
- Image caching

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 1 | 1.3 — Compose + First Safe Failure

**Phase purpose:** Turn the lab into a repeatable multi-service environment.

**Build goals**
- Create Compose file.
- Start the stack.
- Understand service names and networking.
- Use stop/kill/restart.
- Break NGINX safely and observe the symptoms.

**Topics to refer to**
- Compose
- Service networking
- Ports
- Bind mounts
- docker compose ps/logs/exec

**Critical instinct checks — say the answer out loud**
- Why Compose?
- Why use service names?
- docker stop vs docker kill?
- What should curl, ps and ss show after failure?
- Why must the experiment be reversible?

**Extra related topics — do not let these derail the core build**
- Healthchecks
- Restart policies
- Volumes

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 2 | 2.1 — Bind Mounts + Configuration

**Phase purpose:** Understand the host/container boundary.

**Build goals**
- Mount NGINX configuration from the host.
- Change configuration without rebuilding.
- Observe effect and inspect logs.
- Recover from a bad configuration.

**Topics to refer to**
- Bind mounts
- Volumes
- NGINX config
- docker inspect

**Critical instinct checks — say the answer out loud**
- Why mount configuration?
- What lives on host vs container?
- How does a bad config reveal itself?
- Why not rebuild for every config change?

**Extra related topics — do not let these derail the core build**
- Named volumes
- Read-only mounts
- Config templating

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 2 | 2.2 — Linux Diagnostic Toolkit

**Phase purpose:** Train the instinct to investigate before restarting.

**Build goals**
- Practice service, process, port, CPU, memory and disk checks.
- Use logs to find evidence.
- Write what each command proves.

**Topics to refer to**
- systemctl
- journalctl
- ps
- top/htop
- uptime
- ss
- df/du/lsblk
- kill/pkill

**Critical instinct checks — say the answer out loud**
- Can I distinguish dead process vs broken configuration?
- What does ss prove?
- What does curl prove?
- Which command do I choose for CPU, disk and logs — and why?

**Extra related topics — do not let these derail the core build**
- OOM killer
- systemd
- signals
- ncdu
- /proc

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 2 | 2.3 — Failure Is Your Lab

**Phase purpose:** Use controlled chaos to learn diagnosis.

**Build goals**
- Before breaking, write what/how/expected symptom/fix.
- Use docker kill or systemctl stop.
- Check process, port, curl, logs and resources.
- Fix manually.
- Repeat and diagnose before fixing.

**Topics to refer to**
- Safe breaking
- Failure hypothesis
- Evidence collection
- Root cause vs symptom

**Critical instinct checks — say the answer out loud**
- Did the observed result match my prediction?
- Can I explain why curl failed?
- Did I identify the cause or just restart?
- Could the same symptom have another root cause?

**Extra related topics — do not let these derail the core build**
- Resource exhaustion
- Fault injection
- Incident runbooks

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 3 | 3.1 — Prometheus Setup + Targets

**Phase purpose:** Add observability after understanding manual diagnosis.

**Build goals**
- Run Prometheus.
- Configure scrape_interval and evaluation_interval.
- Configure NGINX and node targets/exporters.
- Verify /targets.
- Run `up{job="nginx"}`.

**Topics to refer to**
- Prometheus
- Scraping
- Targets
- Metrics
- prometheus.yml
- PromQL

**Critical instinct checks — say the answer out loud**
- What does Prometheus actually do?
- Who exposes the metrics?
- What is a target?
- What does UP mean?
- Scrape interval vs alert 'for'?

**Extra related topics — do not let these derail the core build**
- Node Exporter
- NGINX exporter
- cAdvisor
- Prometheus API

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 3 | 3.2 — Metric Selection + Alert Rules

**Phase purpose:** Choose a few metrics that answer real operational questions.

**Build goals**
- Understand up, nginx_up and request-counter examples.
- Write NginxDown.
- Add memory-high rule if available.
- Test with a controlled failure.

**Topics to refer to**
- `up == 0`
- `nginx_up == 0`
- `nginx_http_requests_total`
- PromQL
- `for: 2m`
- Alert annotations

**Critical instinct checks — say the answer out loud**
- Can I explain `up == 0`?
- Why wait before alerting?
- What does a request counter tell me?
- Can I reason my way to a disk alert?
- What is symptom vs explanation?

**Extra related topics — do not let these derail the core build**
- Recording rules
- Labels
- Cardinality
- PromQL aggregation

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 3 | 3.3 — Detection Experiment

**Phase purpose:** Prove monitoring detects the failure you previously diagnosed manually.

**Build goals**
- Start stack.
- Confirm targets UP.
- Record metric result.
- Kill NGINX.
- Observe metric transition.
- Observe alert firing after its configured duration.

**Topics to refer to**
- /targets
- /graph
- /alerts
- Prometheus API
- Alert lifecycle

**Critical instinct checks — say the answer out loud**
- Can I predict the metric before breaking?
- Why does it change?
- Why might the alert not fire instantly?
- If target is down but service is healthy, what else could be wrong?

**Extra related topics — do not let these derail the core build**
- Grafana
- Alert testing
- Metric naming

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 4 | 4.1 — Alertmanager + Webhook

**Phase purpose:** Connect detection to an observable recovery trigger.

**Build goals**
- Run Alertmanager.
- Connect Prometheus → Alertmanager.
- Create recovery webhook.
- Log incoming payload.
- Test webhook independently.

**Topics to refer to**
- Routes
- Receivers
- Webhook
- HTTP POST
- Alert payload

**Critical instinct checks — say the answer out loud**
- Why separate alert evaluation from routing?
- What should the webhook receive?
- How do I prove it was called?
- What can fail between Prometheus and webhook?

**Extra related topics — do not let these derail the core build**
- Grouping
- Inhibition
- Retries

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 4 | 4.2 — Security: Secrets + IAM

**Phase purpose:** Protect the recovery path.

**Build goals**
- Use local .env and ignore it.
- Use GitHub Secrets in CI.
- Never hardcode AWS credentials.
- Understand EC2 IAM role/instance profile.
- Keep permissions narrow.

**Topics to refer to**
- Environment variables
- .gitignore
- GitHub Secrets
- IAM role
- Instance profile
- Least privilege
- KMS/Secrets Manager extensions

**Critical instinct checks — say the answer out loud**
- If someone clones my repo, do they get a secret?
- Can image/container inspection expose one?
- Why use EC2 IAM role?
- What exact permission does recovery need?
- Why is least privilege important?

**Extra related topics — do not let these derail the core build**
- Secrets Manager
- KMS
- SSM
- GitHub OIDC

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 4 | 4.3 — Ansible Recovery + Deep Validation

**Phase purpose:** Make recovery a verified outcome.

**Build goals**
- Write Ansible recovery playbook.
- Restart NGINX.
- Wait for startup.
- Check port.
- Call /health.
- Use retries/delay.
- Assert success.

**Topics to refer to**
- Ansible
- systemd
- register
- pause
- wait_for
- uri
- retries/delay
- assert

**Critical instinct checks — say the answer out loud**
- Why is restart ≠ recovery?
- What does port check prove?
- What does /health prove?
- Why retries/delay?
- What should happen if health validation fails?

**Extra related topics — do not let these derail the core build**
- Handlers
- Idempotence
- Recovery-failure alert

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 5 | 5.1 — Terraform + AWS EC2

**Phase purpose:** Make infrastructure reproducible.

**Build goals**
- Define provider/resources.
- Create EC2/security/IAM pieces.
- Run init/plan/apply.
- Inspect state/outputs.
- Destroy/recreate safely in the lab.

**Topics to refer to**
- Provider/resource
- Variables/outputs
- State
- init/plan/apply/destroy
- EC2
- Security Groups
- IAM

**Critical instinct checks — say the answer out loud**
- What problem does Terraform solve?
- What is state?
- Why inspect plan?
- Infrastructure vs configuration?
- Why should EC2 avoid static AWS credentials?

**Extra related topics — do not let these derail the core build**
- Remote state
- Modules
- SSM
- CloudWatch
- KMS

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 5 | 5.2 — Configure the EC2 Host

**Phase purpose:** Separate infrastructure creation from configuration.

**Build goals**
- Connect to EC2.
- Install/configure Docker, NGINX and monitoring.
- Use Ansible for repeatable setup.
- Reproduce from a clean state.

**Topics to refer to**
- Terraform vs Ansible
- Ansible inventory
- EC2 networking
- Security Groups
- SSH/SSM

**Critical instinct checks — say the answer out loud**
- What does Terraform own?
- What does Ansible own?
- If EC2 is replaced, what can be recreated?
- What access is actually necessary?

**Extra related topics — do not let these derail the core build**
- Cloud-init
- Packer
- Immutable infrastructure

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 5 | 5.3 — CI/CD Pipeline

**Phase purpose:** Automate quality gates and image building.

**Build goals**
- Checkout → lint → test → Docker build.
- Use jobs, steps, needs, if and `${{ }}`.
- Condition image build when appropriate.
- Use GitHub Secrets correctly.
- Test through a PR.

**Topics to refer to**
- GitHub Actions
- jobs/steps
- needs
- if
- `${{ }}`
- Secrets
- Conditional Docker build

**Critical instinct checks — say the answer out loud**
- Why lint/test before build?
- Job vs step?
- What does needs do?
- Shell variable vs Actions expression?
- When should Docker build run?

**Extra related topics — do not let these derail the core build**
- Caching
- Artifacts
- Environments
- OIDC

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 6 | 6.1 — Full Integration: Healthy → Break → Detect

**Phase purpose:** Run the entire failure pipeline.

**Build goals**
- Start clean.
- Verify NGINX/Prometheus/Alertmanager.
- Verify target UP and no alert.
- Kill NGINX.
- Observe metric and alert.
- Trace webhook and recovery.

**Topics to refer to**
- Healthy baseline
- Failure
- Prometheus detection
- Alertmanager routing
- Webhook

**Critical instinct checks — say the answer out loud**
- Can I explain every arrow?
- Can I predict the next state before each command?
- Where would I look if the alert never fires?
- Where would I look if the webhook is not called?

**Extra related topics — do not let these derail the core build**
- Failure-mode matrix
- Incident timeline

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 6 | 6.2 — Recovery Validation + Demo

**Phase purpose:** Prove recovery instead of assuming it.

**Build goals**
- Check process/service.
- Check port.
- Check /health.
- Confirm metric returns.
- Confirm alert resolves.
- Capture logs/screenshots.

**Topics to refer to**
- systemctl is-active
- ss/wait_for
- curl/uri
- Prometheus metric
- Alert resolution

**Critical instinct checks — say the answer out loud**
- Can I explain the three validation levels?
- Why is a running process not enough?
- Why is an open port not enough?
- What proves useful application response?
- What if recovery succeeds but the service crashes again?

**Extra related topics — do not let these derail the core build**
- Retries
- Timeouts
- Runbooks
- Feedback-loop alerts

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## DAY 6 | 6.3 — Repeatable Demo + Interview Story

**Phase purpose:** Make the project explainable under pressure.

**Build goals**
- Run demo 3 times: debug, timing, smooth explanation.
- Explain healthy → break → detect → recover → verify.
- Practice failure modes.
- Finish README and architecture diagram.

**Topics to refer to**
- Incident response
- Troubleshooting
- Architecture explanation
- Runbook
- Demo timing

**Critical instinct checks — say the answer out loud**
- What if NGINX doesn't restart?
- What if alert never fires?
- What if Alertmanager receives nothing?
- What if health check times out?
- Where can recovery itself fail?
- How prevent restart loops?

**Extra related topics — do not let these derail the core build**
- SLO/SLI
- High availability
- Multiple replicas
- Canary/blue-green
- Distributed tracing

**Commands I actually learned / used** — 15 empty lines

**Phase notes / what I built / what broke**

---

## REFERENCE — PROMETHEUS

The detailed notes deliberately reduce metric overload: choose a small set of metrics that answer useful operational questions.

| Metric | Meaning | Use |
|---|---|---|
| up | Target reachable? | `up == 0` → target down |
| nginx_up | NGINX process alive? | `nginx_up == 0` |
| nginx_http_requests_total | Requests served | If it stops increasing, investigate |

### REFERENCE CONFIG

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']

  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

rule_files:
  - 'alert_rules.yml'
```

### REFERENCE ALERT

```yaml
- alert: NginxDown
  expr: up{job="nginx"} == 0
  for: 2m
  annotations:
    summary: "NGINX target is unreachable"

- alert: NodeMemoryHigh
  expr: (1 - node_memory_MemAvailable_bytes /
         node_memory_MemTotal_bytes) > 0.9
  for: 5m
```

### CRITICAL CHECKS

- Can I explain scrape_interval vs evaluation_interval?
- Can I explain `up == 0`?
- Why wait 2 minutes?
- Can I reason my way to a disk alert?

---

## REFERENCE — RECOVERY VALIDATION

**Restart ≠ Recovery.** The detailed notes make this a central project requirement.

- **Level 1:** process/service check — useful but shallow.
- **Level 2:** port check — proves something is listening.
- **Level 3:** /health response — proves the service responds successfully.

```
Restart
  ↓
Wait for startup
  ↓
Check port
  ↓
Check /health
  ↓
Assert
  ↓
Recovery verified
```

### REFERENCE ANSIBLE SHAPE

```yaml
- name: Restart NGINX
  systemd:
    name: nginx
    state: restarted
  register: restart_result

- name: Wait
  pause:
    seconds: 3

- name: Verify port
  wait_for:
    host: localhost
    port: 8080
    timeout: 10

- name: Verify health
  uri:
    url: "http://localhost:8080/health"
    status_code: 200
  retries: 5
  delay: 2
```

### CRITICAL CHECKS

- What does each validation layer prove?
- Why is port-open weaker than /health?
- Why do retries/delay matter?
- What happens if validation fails?

---

## REFERENCE — SECURITY

The detailed notes emphasize: no hardcoded secrets, no committed .env, and no long-lived AWS credentials stored on EC2 when an IAM role can be used.

### LOCAL

```
# .env — local only
AWS_REGION=us-east-1
WEBHOOK_TOKEN=local_test_token

# .gitignore
.env
*.pem
```

### CI/CD

Use GitHub Secrets for sensitive CI values; the notes use the `${{ secrets.NAME }}` pattern.

### EC2

Use an IAM role/instance profile so AWS provides credentials to the instance. Keep permissions limited to required actions.

### WEBHOOK

Authenticate the recovery webhook and load its password from an environment variable. Exact Alertmanager authentication syntax should be checked against the version you deploy.

### SECURITY INSTINCTS

- If someone clones my repo, do they get a secret?
- Can image/container inspection reveal one?
- What AWS actions can the EC2 role perform?
- Why is least privilege important?

---

## REFERENCE — REPEATABLE DEMO

| Phase | What happens | Evidence |
|---|---|---|
| 1 Healthy | Start; NGINX responds; target UP; no alert | curl + Prometheus + alert state |
| 2 Break | Kill NGINX deliberately | curl fails + service/container down |
| 3 Detect | Prometheus notices and alert waits | metric changes + alert fires |
| 4 Recover | Alertmanager → webhook → Ansible | recovery logs |
| 5 Verify | Service responds + metric recovers + alert resolves | health + metric + resolved alert |

### PRACTICE THREE TIMES

- Run 1: debug mode.
- Run 2: note timings.
- Run 3: smooth explanation without reading.

### FAILURE MODES

- NGINX doesn't restart → inspect Ansible/recovery logs.
- Alert never fires → inspect Prometheus rule/config.
- Webhook not called → inspect Alertmanager logs.
- Health times out → inspect startup delay/retries.

---

## INTERVIEW BANK

Answer from first principles: problem → component's job → evidence → trade-off.

- Walk me through the architecture from failure to recovery.
- Why Docker? Why Compose?
- Image vs container?
- Why Prometheus if Linux commands exist?
- What is a target? What is a metric? What does `up == 0` mean?
- Why use a 'for' duration?
- Why Alertmanager separately?
- What is a webhook and what can fail?
- Why Ansible for recovery?
- What is idempotence?
- Why is restart not recovery?
- What does /health prove?
- Service down but process alive — how do you troubleshoot?
- CPU 95% — what evidence do you collect?
- Disk 95% — how do you find the source?
- Memory high — what evidence do you collect?
- What is Terraform state?
- Terraform vs Ansible?
- Why an EC2 IAM role?
- Where should CI/CD secrets live?
- GitHub Actions job vs step?
- What does needs do?
- What does `${{ }}` mean?
- Why lint/test before Docker build?
- When should Docker build run conditionally?
- Where can the recovery pipeline itself fail?
- How prevent restart loops?
- How secure the webhook?
- What would you monitor in production?

---

## FINAL PROJECT STORY

By the end, you should be able to tell this story without the PDF:

> "I built a containerized NGINX service and established a healthy baseline. I deliberately introduced a reversible failure. Linux tools let me diagnose the symptom manually. Prometheus then detected the failure through metrics and an alert rule. Alertmanager routed the firing alert to a protected webhook. The recovery path triggered Ansible. I did not call it recovered after a restart: I checked the process, port and health endpoint, then verified the metric recovered and the alert resolved. Terraform made the infrastructure reproducible, and GitHub Actions automated linting, testing and image building."

### FINAL CHECKLIST

- [ ] Service + Docker + Compose work.
- [ ] Failure Lab completed safely.
- [ ] Linux diagnosis used before fixing.
- [ ] Prometheus targets and queries work.
- [ ] Alert rule fires.
- [ ] Alertmanager routes.
- [ ] Webhook is observable/protected.
- [ ] Ansible recovery works.
- [ ] Recovery is deeply validated.
- [ ] Terraform creates infrastructure.
- [ ] EC2 IAM role is understood.
- [ ] CI/CD works.
- [ ] Secrets are not hardcoded.
- [ ] End-to-end demo works.
- [ ] README + architecture diagram are complete.
- [ ] I can explain every arrow without notes.

**What I built**

**What I learned / instincts I developed**

**What broke + how I diagnosed it**

**What I want to explore next**
