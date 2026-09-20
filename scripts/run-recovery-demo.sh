#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_FILE="${EVIDENCE_FILE:-${ROOT_DIR}/journal/evidence/day6-${TIMESTAMP}.log}"
POLL_SECONDS="${POLL_SECONDS:-10}"
RECOVERY_TIMEOUT_SECONDS="${RECOVERY_TIMEOUT_SECONDS:-240}"
RESOLUTION_TIMEOUT_SECONDS="${RESOLUTION_TIMEOUT_SECONDS:-120}"

PROMETHEUS_URL="http://127.0.0.1:9090"
ALERTMANAGER_URL="http://127.0.0.1:9093"
NGINX_HEALTH_URL="http://127.0.0.1:8083/health"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo: sudo bash scripts/run-recovery-demo.sh" >&2
  exit 1
fi

for command in docker curl python3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command is missing: $command" >&2
    exit 1
  fi
done

cd "$ROOT_DIR"
mkdir -p "$(dirname "$EVIDENCE_FILE")"
exec > >(tee -a "$EVIDENCE_FILE") 2>&1

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
original_restart_policy="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' nginx)"
demo_passed=false

cleanup() {
  local status=$?
  trap - EXIT
  set +e

  echo
  echo "=== CLEANUP ==="
  docker update --restart=unless-stopped nginx >/dev/null 2>&1

  if [[ "$(docker inspect -f '{{.State.Running}}' nginx 2>/dev/null)" != "true" ]]; then
    echo "Automated recovery did not leave NGINX running; starting it manually."
    docker start nginx >/dev/null 2>&1
  fi

  for _ in $(seq 1 12); do
    if curl -fsS "$NGINX_HEALTH_URL" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  echo "restored_restart_policy=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' nginx 2>/dev/null)"
  if curl -fsS "$NGINX_HEALTH_URL" >/dev/null 2>&1; then
    echo "cleanup_health=ok"
  else
    echo "cleanup_health=failed"
  fi
  echo "evidence_file=$EVIDENCE_FILE"

  if [[ "$demo_passed" == "true" ]]; then
    exit 0
  fi
  exit "$status"
}
trap cleanup EXIT

metric_value() {
  curl -fsS --get --data-urlencode 'query=nginx_up' "${PROMETHEUS_URL}/api/v1/query" |
    python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "missing")'
}

rule_state() {
  curl -fsS "${PROMETHEUS_URL}/api/v1/rules" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((r["state"] for g in d["data"]["groups"] for r in g["rules"] if r["name"]=="NginxDown"), "missing"))'
}

prometheus_alert_count() {
  curl -fsS "${PROMETHEUS_URL}/api/v1/alerts" |
    python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]["alerts"]))'
}

alertmanager_alert_count() {
  curl -fsS "${ALERTMANAGER_URL}/api/v2/alerts" |
    python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'
}

container_running() {
  docker inspect -f '{{.State.Running}}' nginx 2>/dev/null || echo false
}

health_state() {
  if curl -fsS --max-time 3 "$NGINX_HEALTH_URL" >/dev/null 2>&1; then
    echo ok
  else
    echo down
  fi
}

echo "=== DAY 6 SELF-HEALING DEMO ==="
echo "started_at=$started_at"
echo "host=$(hostname)"
echo "original_restart_policy=$original_restart_policy"
echo

echo "=== PHASE 1: HEALTHY BASELINE ==="
docker compose ps
curl -fsS "$NGINX_HEALTH_URL" | grep -qx 'ok'
curl -fsS "${PROMETHEUS_URL}/-/ready" >/dev/null
curl -fsS "${ALERTMANAGER_URL}/-/ready" >/dev/null

baseline_metric="$(metric_value)"
baseline_rule="$(rule_state)"
baseline_prometheus_alerts="$(prometheus_alert_count)"
baseline_alertmanager_alerts="$(alertmanager_alert_count)"
echo "nginx_up=$baseline_metric rule=$baseline_rule prometheus_alerts=$baseline_prometheus_alerts alertmanager_alerts=$baseline_alertmanager_alerts"

if [[ "$baseline_metric" != "1" || "$baseline_rule" != "inactive" || "$baseline_prometheus_alerts" != "0" ]]; then
  echo "Baseline is not clean; refusing to run a destructive demo." >&2
  exit 1
fi

echo
echo "=== PHASE 2: CONTROLLED FAILURE ==="
docker update --restart=no nginx >/dev/null
docker kill nginx >/dev/null
sleep 2

echo "nginx_running=$(container_running) health=$(health_state)"
if [[ "$(container_running)" != "false" ]]; then
  echo "NGINX did not stop as expected." >&2
  exit 1
fi

echo
echo "=== PHASE 3: DETECTION AND AUTOMATED RECOVERY ==="
recovered=false
saw_metric_zero=false
saw_pending=false
saw_firing=false

for ((elapsed=0; elapsed<=RECOVERY_TIMEOUT_SECONDS; elapsed+=POLL_SECONDS)); do
  if (( elapsed > 0 )); then
    sleep "$POLL_SECONDS"
  fi

  metric="$(metric_value)"
  state="$(rule_state)"
  running="$(container_running)"
  health="$(health_state)"
  printf 't=%3ss nginx_up=%s alert=%-8s running=%s health=%s\n' "$elapsed" "$metric" "$state" "$running" "$health"

  [[ "$metric" == "0" ]] && saw_metric_zero=true
  [[ "$state" == "pending" ]] && saw_pending=true
  [[ "$state" == "firing" ]] && saw_firing=true

  if [[ "$running" == "true" && "$health" == "ok" && "$saw_firing" == "true" ]]; then
    recovered=true
    break
  fi
done

if [[ "$recovered" != "true" ]]; then
  echo "Automatic recovery was not verified within ${RECOVERY_TIMEOUT_SECONDS}s." >&2
  exit 1
fi

if [[ "$saw_metric_zero" != "true" || "$saw_pending" != "true" || "$saw_firing" != "true" ]]; then
  echo "The complete metric/alert lifecycle was not observed." >&2
  exit 1
fi

echo
echo "=== PHASE 4: DEEP VALIDATION AND ALERT RESOLUTION ==="
resolved=false
for ((elapsed=0; elapsed<=RESOLUTION_TIMEOUT_SECONDS; elapsed+=POLL_SECONDS)); do
  if (( elapsed > 0 )); then
    sleep "$POLL_SECONDS"
  fi

  metric="$(metric_value)"
  state="$(rule_state)"
  prom_alerts="$(prometheus_alert_count)"
  am_alerts="$(alertmanager_alert_count)"
  health="$(health_state)"
  printf 'resolution_t=%3ss nginx_up=%s alert=%-8s prometheus_alerts=%s alertmanager_alerts=%s health=%s\n' \
    "$elapsed" "$metric" "$state" "$prom_alerts" "$am_alerts" "$health"

  if [[ "$metric" == "1" && "$state" == "inactive" && "$prom_alerts" == "0" && "$am_alerts" == "0" && "$health" == "ok" ]]; then
    resolved=true
    break
  fi
done

if [[ "$resolved" != "true" ]]; then
  echo "Recovery occurred, but alert resolution was not verified within ${RESOLUTION_TIMEOUT_SECONDS}s." >&2
  exit 1
fi

webhook_logs=""
for _ in $(seq 1 7); do
  webhook_logs="$(docker logs recovery-webhook --since "$started_at" 2>&1)"
  if grep -q 'alert received: status=resolved' <<< "$webhook_logs"; then
    break
  fi
  sleep 10
done
printf '%s\n' "$webhook_logs" | grep -E 'alert received|running recovery|recovery succeeded|alert resolved' || true

if ! grep -q 'alert received: status=firing' <<< "$webhook_logs"; then
  echo "Webhook firing notification evidence is missing." >&2
  exit 1
fi
if ! grep -q 'recovery succeeded and passed validation' <<< "$webhook_logs"; then
  echo "Webhook recovery-success evidence is missing." >&2
  exit 1
fi
if ! grep -q 'alert received: status=resolved' <<< "$webhook_logs"; then
  echo "Webhook resolved-notification evidence is missing." >&2
  exit 1
fi

echo
echo "=== RESULT: PASS ==="
echo "Observed: nginx_up 1→0→1, alert inactive→pending→firing→inactive, authenticated Ansible recovery, HTTP health, and resolved notification."
demo_passed=true
