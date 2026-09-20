# Self-Healing Infrastructure — Project Context

Read this file first when resuming work. It records the current architecture, verified behavior, operational findings, and remaining work.

## Goal

```text
NGINX failure
→ nginx-exporter reports nginx_up=0
→ Prometheus waits 2 minutes and fires NginxDown
→ Alertmanager routes an authenticated webhook
→ webhook applies restart-loop guards and invokes Ansible
→ Ansible restarts NGINX
→ process, port and /health are validated
→ nginx_up returns to 1 and the alert resolves
```

Main guide: `SELF-HEALING-PROJECT-GUIDE.md`. Daily evidence: `journal/day-01.md` through `journal/day-07.md`.

## Git and workspace state

- Remote: `https://github.com/pinkprincess536/Self-healing-infra.git`
- Current branch: `main`
- `main` and `origin/main` contain the original Day 5 infrastructure deployment commit `a294267`.
- The permanent EC2 token-permission fix is currently modified locally and awaiting this commit:
  - `docker-compose.yml`
  - `infrastructure/ansible/configure_ec2.yml`
  - `journal/day-05.md`
  - this context file and Terraform README
- `journal/day-02.md` contains unrelated user notes and must remain unstaged.
- `journal/day-05-2.md` is an untracked raw chat transcript; preserve it, but do not include it in the polished Day 5 fix commit.

## Current local/EC2 stack

| Service | Purpose | Exposure |
|---|---|---|
| NGINX | Demo service with `/health` and `/stub_status` | Host/EC2 port 8083 |
| tester | Internal DNS and curl checks | Compose network only |
| nginx-exporter | Converts NGINX status to Prometheus metrics | Host loopback 9113 |
| Prometheus | Scrapes metrics and evaluates alerts | Host loopback 9090 |
| Alertmanager | Groups/routes alerts to recovery | Host loopback 9093 |
| recovery-webhook | Authenticates alerts and runs Ansible | Compose network port 5000 only |

Important metric distinction:

- `nginx_up == 0` means NGINX is unavailable and is the recovery signal.
- `up{job="nginx"} == 0` means the exporter itself is unavailable; NGINX health is unknown.

## Verified local work (Days 1–4)

- Day 1: containerized NGINX, Compose, static page and `/health`.
- Day 2: bind mounts, Compose DNS, diagnostics and controlled failure.
- Day 3: exporter, Prometheus, corrected metrics and alert lifecycle.
- Day 4: Alertmanager, Bearer-authenticated webhook, cooldown/circuit breaker, Ansible recovery, three-level validation and resolved handling.

The complete local failure/recovery loop passed before AWS deployment.

## Day 5 AWS infrastructure

Terraform source is under `infrastructure/terraform` and is pinned to:

- Terraform 1.16.2
- HashiCorp AWS provider 6.65.0

Terraform creates:

- dedicated VPC and public subnet;
- internet gateway, route table and association;
- Security Group allowing TCP 8083 only from the operator's `/32`;
- no SSH ingress by default;
- Canonical Ubuntu 24.04 `t3.small` EC2;
- encrypted 20 GiB gp3 root disk;
- IMDSv2 requirement;
- IAM role/profile with `AmazonSSMManagedInstanceCore`.

Terraform validation evidence:

```text
terraform fmt -check: passed
terraform validate: Success
terraform test: 2 passed, 0 failed
mock safe plan: 12 add, 0 change, 0 destroy
world-open 0.0.0.0/0 test: correctly rejected
```

Real AWS deployment:

```text
Region: us-east-1
EC2 ID: i-0058e02a09ef23ef8
Public IP at deployment: 100.59.34.88
Private IP: 10.42.1.160
Security Group: sg-05268d37f2034b849
SSM: Online
```

These values are environment-specific and may change after replacement.

## AWS permission lessons

Terraform initially partially applied networking, then failed because the operator lacked `iam:CreateRole`. A later role refresh required `iam:ListRolePolicies`. The old saved plan became stale after state changed, so a fresh plan was required. Terraform marked the incompletely read role tainted and replaced it safely after permissions were corrected.

Session Manager has two permission sides:

- EC2 role: lets the machine register with SSM.
- Operator policy: allows `ssm:StartSession` and approved session documents.

The project uses SSM instead of public SSH or a private key.

## EC2 configuration

`infrastructure/ansible/bootstrap-ec2.sh` installs Git/Ansible, clones `main` to `/opt/self-healing`, and runs `configure_ec2.yml`.

Ansible successfully completed:

```text
ok=18 changed=2 unreachable=0 failed=0
```

It verified:

- Docker and Compose installed;
- `self-healing.service` installed and enabled;
- systemd reports `active (exited)`, expected for the oneshot unit;
- all six containers started;
- NGINX `/health` returned 200 `ok`;
- Prometheus and Alertmanager readiness returned 200;
- internal webhook returned `status=ok`.

## Real EC2 incident and permanent fix

During the controlled EC2 failure test:

```text
NGINX container: Exited (137), matching deliberate SIGKILL
nginx_up: 0
NginxDown: firing
Prometheus → Alertmanager connection: active
Alertmanager: held active NginxDown alert
Webhook: no request received
```

Alertmanager logs exposed the root cause:

```text
unable to read authorization credentials file
/etc/alertmanager/webhook_token: permission denied
```

Original Linux token permissions were `root:root 0600`. Alertmanager runs as non-root UID/GID 65534, so it could not read the token and correctly refused to send an unauthenticated recovery request.

Permanent fix:

- Compose explicitly runs Alertmanager as `65534:65534`.
- Ansible creates the token as `root:65534` mode `0640`.
- Root can read/write, Alertmanager's group can read, everyone else has no access.

The user applied the same ownership/mode correction on EC2 and reported successful recovery. Final filtered webhook/resolved evidence should still be captured if available.

## Security model

- Real secrets, `.tfvars`, Terraform state/cache and saved plan files are gitignored.
- The token never enters Terraform state.
- `/recover` requires a Bearer token, `status=firing`, and `NginxDown`.
- Resolved events are logged and ignored.
- Alertmanager repeat interval, webhook cooldown, attempt window and timeout prevent restart loops.
- Monitoring ports bind to loopback and are accessed through SSM tunnels.
- The Docker socket remains a deliberate single-host lab limitation because it gives powerful host control. This is not a production security boundary.

## Windows/Linux reminders

- Windows prompt: `PS C:\...>`; use PowerShell syntax, backtick continuation and `curl.exe`.
- EC2 prompt: `$`; use Linux paths, `curl`, `sudo`, and backslash continuation.
- A bare URL is not a command.
- `/tmp` and `/opt` are Linux paths.
- Dynamic operator IP changes require a new restricted Terraform CIDR plan; never use `0.0.0.0/0`.

## Current remaining work

1. Commit and push the permanent token-permission fix and polished Day 5 journal.
2. Confirm on EC2:
   - token is `root:65534 640`;
   - NGINX is healthy;
   - NGINX restart policy is restored to `unless-stopped`;
   - active Prometheus alerts are empty;
   - recovery webhook logs show firing → recovery → resolved, if logs remain.
3. Optionally reboot or replace EC2 to prove reproducibility.
4. Destroy AWS resources after evidence is saved to stop charges.
5. Begin Day 6 CI/CD and controlled resource-failure work.
