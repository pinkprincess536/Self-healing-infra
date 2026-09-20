"""
Recovery webhook — the bridge between Alertmanager and Ansible.

Flow:
  Alertmanager POSTs the firing alert here  ->  we authenticate it
  ->  we check restart-loop guards  ->  we run the Ansible playbook
  ->  we return the playbook's verdict (and log everything).

Deliberately small and boring: this sits on the recovery path, so it should be
easy to read and easy to reason about when it's the thing that's broken.
"""

import hmac
import json
import logging
import os
import subprocess
import threading
import time

from flask import Flask, jsonify, request

# ---------------------------------------------------------------- config

PLAYBOOK = os.environ.get("PLAYBOOK_PATH", "/ansible/restart_nginx.yml")
INVENTORY = os.environ.get("INVENTORY_PATH", "/ansible/inventory.ini")

# Restart-loop guards. Automated recovery that retries forever turns a small
# outage into a crash loop, so recovery is rate limited on two axes:
#   COOLDOWN     — minimum seconds between two recovery runs
#   MAX_ATTEMPTS — max runs allowed inside ATTEMPT_WINDOW before we refuse and
#                  leave it for a human (fail loudly rather than thrash)
COOLDOWN_SECONDS = int(os.environ.get("RECOVERY_COOLDOWN_SECONDS", "60"))
MAX_ATTEMPTS = int(os.environ.get("RECOVERY_MAX_ATTEMPTS", "3"))
ATTEMPT_WINDOW_SECONDS = int(os.environ.get("RECOVERY_ATTEMPT_WINDOW_SECONDS", "600"))

PLAYBOOK_TIMEOUT_SECONDS = int(os.environ.get("PLAYBOOK_TIMEOUT_SECONDS", "120"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("recovery-webhook")


def _load_token() -> str:
    """Read the shared secret from a mounted file, falling back to an env var.

    A file is preferred so the secret never appears in `docker inspect` output
    or in the committed Compose file — Alertmanager reads the exact same file
    via `credentials_file`, so there's a single source of truth.
    """
    token_file = os.environ.get("WEBHOOK_TOKEN_FILE")
    if token_file and os.path.exists(token_file):
        with open(token_file, "r", encoding="utf-8") as handle:
            return handle.read().strip()
    return (os.environ.get("WEBHOOK_TOKEN") or "").strip()


TOKEN = _load_token()
if not TOKEN:
    # Refuse to start unauthenticated. An open recovery endpoint would let
    # anyone who can reach the port restart the service at will.
    raise SystemExit(
        "FATAL: no webhook token configured. Set WEBHOOK_TOKEN_FILE or WEBHOOK_TOKEN."
    )

# ---------------------------------------------------------------- state

app = Flask(__name__)

_lock = threading.Lock()
_last_run_at = 0.0
_recent_attempts: list[float] = []


def _authorized(req) -> bool:
    """Constant-time comparison of the Bearer token."""
    header = req.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return False
    presented = header[len("Bearer ") :].strip()
    return hmac.compare_digest(presented, TOKEN)


def _guard_check(now: float) -> tuple[bool, str]:
    """Return (allowed, reason). Assumes _lock is held."""
    if now - _last_run_at < COOLDOWN_SECONDS:
        wait = int(COOLDOWN_SECONDS - (now - _last_run_at))
        return False, f"cooldown active, {wait}s remaining"

    recent = [t for t in _recent_attempts if now - t < ATTEMPT_WINDOW_SECONDS]
    if len(recent) >= MAX_ATTEMPTS:
        return False, (
            f"circuit open: {len(recent)} recovery attempts in the last "
            f"{ATTEMPT_WINDOW_SECONDS}s — needs human investigation"
        )
    return True, ""


def _run_playbook() -> tuple[bool, str]:
    """Run ansible-playbook and return (success, combined output)."""
    cmd = ["ansible-playbook", "-i", INVENTORY, PLAYBOOK]
    log.info("running recovery: %s", " ".join(cmd))
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=PLAYBOOK_TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False, f"playbook timed out after {PLAYBOOK_TIMEOUT_SECONDS}s"

    output = (result.stdout or "") + (result.stderr or "")
    return result.returncode == 0, output


# ---------------------------------------------------------------- routes


@app.get("/healthz")
def healthz():
    """Liveness for the webhook itself — separate from NGINX's /health."""
    return jsonify(status="ok", service="recovery-webhook"), 200


@app.get("/status")
def status():
    """Expose the guard state so restart-loop behaviour is observable."""
    now = time.time()
    with _lock:
        recent = [t for t in _recent_attempts if now - t < ATTEMPT_WINDOW_SECONDS]
        return (
            jsonify(
                last_run_at=_last_run_at or None,
                seconds_since_last_run=int(now - _last_run_at) if _last_run_at else None,
                attempts_in_window=len(recent),
                max_attempts=MAX_ATTEMPTS,
                cooldown_seconds=COOLDOWN_SECONDS,
                attempt_window_seconds=ATTEMPT_WINDOW_SECONDS,
            ),
            200,
        )


@app.post("/recover")
def recover():
    global _last_run_at

    if not _authorized(request):
        log.warning("rejected unauthorized request from %s", request.remote_addr)
        return jsonify(status="unauthorized"), 401

    payload = request.get_json(silent=True) or {}

    # Log the payload — "how do I prove the webhook was called?" needs an answer
    # that doesn't depend on guessing.
    log.info(
        "alert received: status=%s alerts=%s",
        payload.get("status"),
        [a.get("labels", {}).get("alertname") for a in payload.get("alerts", [])],
    )
    log.debug("full payload: %s", json.dumps(payload)[:2000])

    # Alertmanager also POSTs when an alert RESOLVES (send_resolved: true).
    # Resolved means the service is healthy again — recovering would be wrong.
    if payload.get("status") == "resolved":
        log.info("alert resolved — no recovery needed")
        return jsonify(status="ignored", reason="alert resolved"), 200

    # Do not trust the caller merely because it has the token. Alertmanager's
    # route is the first allow-list, and the action endpoint independently
    # enforces both the event state and the exact recoverable alert name.
    if payload.get("status") != "firing":
        log.warning("rejected payload with non-firing status")
        return jsonify(status="rejected", reason="status must be firing"), 400

    alert_names = {
        alert.get("labels", {}).get("alertname")
        for alert in payload.get("alerts", [])
    }
    if "NginxDown" not in alert_names:
        log.warning("rejected non-recoverable alerts: %s", sorted(str(name) for name in alert_names))
        return jsonify(status="rejected", reason="NginxDown alert required"), 400

    now = time.time()
    with _lock:
        allowed, reason = _guard_check(now)
        if not allowed:
            log.warning("recovery suppressed: %s", reason)
            return jsonify(status="suppressed", reason=reason), 429
        _last_run_at = now
        _recent_attempts.append(now)

    success, output = _run_playbook()
    tail = output.strip().splitlines()[-25:]

    if success:
        log.info("recovery succeeded and passed validation")
        return jsonify(status="recovered", verified=True, output=tail), 200

    log.error("recovery FAILED — playbook output tail: %s", tail)
    return jsonify(status="failed", verified=False, output=tail), 500


if __name__ == "__main__":
    log.info(
        "starting recovery webhook (cooldown=%ss max_attempts=%s/%ss)",
        COOLDOWN_SECONDS,
        MAX_ATTEMPTS,
        ATTEMPT_WINDOW_SECONDS,
    )
    # Bound to 0.0.0.0 so Alertmanager can reach it over the Compose network.
    # Auth is enforced on /recover; the port is NOT published to the host.
    app.run(host="0.0.0.0", port=5000)
