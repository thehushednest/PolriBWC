#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HOST_ADDRESS="${1:-0.0.0.0}"
PORT="${2:-8787}"
DART_BIN="${DART_BIN:-/home/senopati/flutter/bin/dart}"
PID_FILE="${PROJECT_ROOT}/server/server.pid"
LOG_FILE="${PROJECT_ROOT}/server/server.log"

find_running_server_pid() {
  pgrep -f "server/bin/polri_bwc_server.dart" | head -n 1 || true
}

if [[ ! -x "${DART_BIN}" ]]; then
  echo "Dart executable tidak ditemukan atau tidak executable: ${DART_BIN}" >&2
  exit 1
fi

if [[ -f "${PID_FILE}" ]]; then
  EXISTING_PID="$(cat "${PID_FILE}")"
  if [[ -n "${EXISTING_PID}" ]] && kill -0 "${EXISTING_PID}" 2>/dev/null; then
    echo "Server sudah berjalan dengan PID ${EXISTING_PID}" >&2
    exit 0
  fi
  rm -f "${PID_FILE}"
fi

RUNNING_PID="$(find_running_server_pid)"
if [[ -n "${RUNNING_PID}" ]]; then
  echo "${RUNNING_PID}" > "${PID_FILE}"
  echo "Server sudah berjalan dengan PID ${RUNNING_PID}" >&2
  exit 0
fi

cd "${PROJECT_ROOT}"
nohup "${DART_BIN}" server/bin/polri_bwc_server.dart --host "${HOST_ADDRESS}" --port "${PORT}" \
  >> "${LOG_FILE}" 2>&1 &
SERVER_PID=$!
echo "${SERVER_PID}" > "${PID_FILE}"

sleep 1

if kill -0 "${SERVER_PID}" 2>/dev/null; then
  echo "Polri BWC local server berjalan di background"
  echo "PID: ${SERVER_PID}"
  echo "Log: ${LOG_FILE}"
  echo "API: http://${HOST_ADDRESS}:${PORT}/api/v1"
  echo "PTT: tcp://${HOST_ADDRESS}:$((PORT + 1))"
else
  echo "Gagal menyalakan server. Cek log: ${LOG_FILE}" >&2
  exit 1
fi
