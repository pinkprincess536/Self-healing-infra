#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_URL="${REPOSITORY_URL:-https://github.com/pinkprincess536/Self-healing-infra.git}"
REPOSITORY_VERSION="${REPOSITORY_VERSION:-main}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/self-healing}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash bootstrap-ec2.sh" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ansible-core git

if [[ -d "${DEPLOY_ROOT}/.git" ]]; then
  git -C "${DEPLOY_ROOT}" fetch --prune origin
  git -C "${DEPLOY_ROOT}" checkout "${REPOSITORY_VERSION}"
  git -C "${DEPLOY_ROOT}" pull --ff-only origin "${REPOSITORY_VERSION}"
else
  git clone --branch "${REPOSITORY_VERSION}" --single-branch \
    "${REPOSITORY_URL}" "${DEPLOY_ROOT}"
fi

cd "${DEPLOY_ROOT}"

# vars_prompt asks for the token twice with hidden input. It is written only to
# /opt/self-healing/secrets/webhook_token (root:root 0600), never Terraform.
exec ansible-playbook \
  -i infrastructure/ansible/inventory.local.ini \
  infrastructure/ansible/configure_ec2.yml
