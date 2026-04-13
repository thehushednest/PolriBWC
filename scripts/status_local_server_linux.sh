#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PID_FILE="${PROJECT_ROOT}/server/server.pid"
LOG_FILE="${PROJECT_ROOT}/server/server.log"

find_running_server_pid() {
  pgrep -f "server/bin/polri_bwc_server.dart" | head -n 1 || true
}

if [[ -f "${PID_FILE}" ]]; then
  SERVER_PID="$(cat "${PID_FILE}")"
  if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo "Server aktif dengan PID ${SERVER_PID}"
    exit 0
  fi
  RUNNING_PID="$(find_running_server_pid)"
  if [[ -n "${RUNNING_PID}" ]]; then
    echo "${RUNNING_PID}" > "${PID_FILE}"
    echo "Server aktif dengan PID ${RUNNING_PID} (PID file diperbarui)"
    exit 0
  fi
  rm -f "${PID_FILE}"
  echo "PID file stale dihapus. Server tidak aktif."
  if [[ -f "${LOG_FILE}" ]]; then
    echo "Log terakhir: ${LOG_FILE}"
  fi
  exit 1
fi

RUNNING_PID="$(find_running_server_pid)"
if [[ -n "${RUNNING_PID}" ]]; then
  echo "${RUNNING_PID}" > "${PID_FILE}"
  echo "Server aktif dengan PID ${RUNNING_PID} (PID file dibuat ulang)"
  exit 0
fi

echo "Server tidak aktif."
if [[ -f "${LOG_FILE}" ]]; then
  echo "Log terakhir: ${LOG_FILE}"
fi
exit 1
