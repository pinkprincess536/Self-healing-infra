# Conclusion — Part 1: Current Recovery Scope and Test Cases

## Do we need to formulate test cases?

Yes. Test cases prove what the system can recover from and, just as importantly, what it cannot recover from.

A test case should record:

```text
Test name:
Starting condition:
Action:
Expected metric:
Expected alert:
Expected recovery:
Evidence collected:
Cleanup:
Actual result:
Pass or fail:
```

## What recovery can we handle right now?

Currently, there is only **one automatic recovery action**:

```text
Restart the existing NGINX Docker container
```

The Ansible recovery command is effectively:

```bash
docker restart nginx
```

After restarting, Ansible verifies:

```text
Container running
→ port 80 open
→ /health returns HTTP 200 and "ok"
```

## Failures we can currently recover from

### 1. NGINX container was stopped

Example:

```bash
sudo docker stop nginx
```

Recovery flow:

```text
Prometheus sees nginx_up = 0
→ alert fires
→ Ansible runs docker restart nginx
→ NGINX returns
```

### 2. NGINX container was killed

Example:

```bash
sudo docker kill nginx
```

The container still exists, so Ansible can restart it. This is the main failure we tested locally and on AWS EC2.

### 3. NGINX is running but not responding

If NGINX hangs or its `/stub_status` endpoint becomes unreachable:

```text
nginx_up becomes 0
→ NginxDown fires
→ container is restarted
```

A restart may fix a temporary process hang.

### 4. Temporary NGINX startup delay

The Ansible playbook does not check health only once. It waits and retries:

```text
Restart NGINX
→ wait
→ check port
→ check /health
→ retry if startup is slow
```

This handles a service that needs a few seconds to become ready.

## What we cannot currently recover from

### 1. NGINX container was deleted

Example:

```bash
sudo docker rm -f nginx
```

Ansible cannot run `docker restart nginx` because the container no longer exists.

A possible future recovery would be:

```bash
docker compose up -d nginx
```

### 2. Docker itself is down

If the Docker daemon stops, all containers on the same host stop:

```text
NGINX stops
Prometheus stops
Alertmanager stops
Webhook stops
```

Nothing remains available to perform recovery.

Possible future solutions include systemd monitoring Docker, AWS EC2 Auto Recovery, an external monitoring host, or an ECS service scheduler.

### 3. EC2 is down

All monitoring and recovery services currently run on the same EC2 instance.

If EC2 crashes:

```text
NGINX unavailable
Prometheus unavailable
Alertmanager unavailable
Webhook unavailable
Ansible unavailable
```

The system cannot heal its own host. Possible future solutions include external Prometheus, CloudWatch, EC2 Auto Recovery, an Auto Scaling Group, or ECS across multiple instances.

### 4. Bad NGINX configuration

If `nginx.conf` is invalid, restarting uses the same broken file:

```text
Restart
→ same invalid configuration
→ NGINX fails again
```

Ansible correctly reports recovery failure, but it cannot repair the configuration. A future solution could validate with `nginx -t` before deployment and roll back to the last valid configuration or image.

### 5. Application returns incorrect content

Prometheus currently checks whether the exporter can reach NGINX. It does not continuously confirm that `/health` returns the correct application response.

NGINX could be running while the application is logically broken, and `nginx_up` might remain `1`.

A future improvement is Prometheus Blackbox Exporter:

```text
Blackbox Exporter requests /health
→ checks status, timeout and content
→ exposes a metric
→ Prometheus alerts on application-level failure
```

### 6. NGINX exporter is down

We have a separate alert:

```text
NginxExporterDown
```

It intentionally does not restart NGINX because:

```text
Exporter down does not prove NGINX is down
```

Blindly restarting NGINX would be guessing.

### 7. Prometheus, Alertmanager or webhook is down

The recovery chain breaks if any of these components is unavailable. We currently do not have a second external system that monitors and recovers them.

### 8. CPU, memory or disk pressure

We have not yet created CPU, memory or disk alerts and recovery actions. The current project cannot automatically recover from resource-pressure problems.

### 9. Network or DNS failure

A network problem may make `nginx_up` become `0`, but restarting NGINX may not repair networking.

The playbook will detect that health still fails, but it cannot automatically repair the network.

## Minimum test cases

| Test | What we do | Expected result |
|---|---|---|
| Healthy baseline | Leave everything running | `nginx_up=1`, no alert, no recovery |
| NGINX killed | `docker kill nginx` | Alert fires, Ansible restarts NGINX, health returns |
| NGINX stopped | `docker stop nginx` | Alert fires and the existing container is restarted |
| Invalid token | Call webhook without the token | HTTP 401, no recovery |
| Wrong alert | Send `OtherAlert` | HTTP 400, no recovery |
| Duplicate recovery | Send two valid requests quickly | First accepted, second HTTP 429 |
| Resolved alert | Send `status=resolved` | Logged and ignored, no recovery |
| Exporter stopped | Stop the exporter | `NginxExporterDown` fires; NGINX is not restarted blindly |
| Recovery failure | Make restart or health validation fail safely | Webhook returns 500 and does not claim success |
| Playbook timeout | Simulate Ansible taking too long | Timeout is reported as failure |

## Example test case

```text
Test name: NGINX hard failure

Starting condition:
NGINX healthy, nginx_up=1, no alert.

Action:
docker kill nginx

Expected metric:
nginx_up becomes 0.

Expected alert:
NginxDown becomes pending, then firing.

Expected recovery:
Alertmanager calls the authenticated webhook.
The webhook invokes Ansible.
Ansible restarts NGINX.

Evidence:
Prometheus rule state, Alertmanager alert, webhook logs,
docker compose ps, and /health response.

Cleanup:
Restore restart policy to unless-stopped.

Actual result:
NGINX restarted and /health returned HTTP 200.

Result:
PASS
```

## Recovery validation levels

A successful restart command is not enough. Recovery is verified at multiple levels:

```text
Level 1 → NGINX container is running
Level 2 → port 80 accepts connections
Level 3 → /health returns HTTP 200 and "ok"
Level 4 → nginx_up returns to 1
Level 5 → NginxDown alert resolves
```

## Final conclusion

Right now, the project is not a general-purpose self-healing platform.

It is specifically:

> **A verified automatic NGINX container restart system for process-level failure on a healthy Docker/EC2 host.**

That is still a valid and useful system because it:

- Defines exactly which failure it can handle.
- Detects the failure with the correct metric.
- Waits before acting to avoid temporary noise.
- Authenticates the recovery request.
- Limits repeated recovery attempts.
- Restarts the service through Ansible.
- Verifies process, port and application health.
- Confirms the metric recovered and the alert resolved.
- Clearly documents the failures it cannot safely repair.

A trustworthy self-healing system should not claim it can fix every problem. It should act only on known failure modes, use a safe recovery action, verify the result, and stop when human investigation is needed.
