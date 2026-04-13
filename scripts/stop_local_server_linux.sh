#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PID_FILE="${PROJECT_ROOT}/server/server.pid"

find_running_server_pid() {
  pgrep -f "server/bin/polri_bwc_server.dart" | head -n 1 || true
}

if [[ ! -f "${PID_FILE}" ]]; then
  echo "PID file tidak ditemukan. Server kemungkinan tidak berjalan."
  exit 0
fi

SERVER_PID="$(cat "${PID_FILE}")"

if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
  kill "${SERVER_PID}"
  echo "Menghentikan server PID ${SERVER_PID}"
else
  RUNNING_PID="$(find_running_server_pid)"
  if [[ -n "${RUNNING_PID}" ]]; then
    kill "${RUNNING_PID}"
    echo "Menghentikan server PID ${RUNNING_PID}"
  else
    echo "Process PID ${SERVER_PID} tidak aktif."
  fi
fi

rm -f "${PID_FILE}"
