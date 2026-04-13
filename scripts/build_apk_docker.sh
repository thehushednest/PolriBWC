#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_NAME="${POLRI_BWC_DOCKER_IMAGE:-polri-bwc-apk-builder:3.41.6}"
OUTPUT_DIR="${POLRI_BWC_OUTPUT_DIR:-${REPO_ROOT}/out/docker-apk}"

mkdir -p "${OUTPUT_DIR}"

if [[ $# -eq 0 ]]; then
  BUILD_ARGS=(--debug)
else
  BUILD_ARGS=("$@")
fi

docker buildx build \
  --platform linux/amd64 \
  -f "${REPO_ROOT}/docker/apk-builder.Dockerfile" \
  -t "${IMAGE_NAME}" \
  --load \
  "${REPO_ROOT}"

docker run --rm \
  --platform linux/amd64 \
  -v "${REPO_ROOT}:/workspace" \
  -v "${OUTPUT_DIR}:/out" \
  -w /workspace \
  -e POLRI_BWC_USE_MOCK="${POLRI_BWC_USE_MOCK:-}" \
  -e POLRI_BWC_API_BASE_URL="${POLRI_BWC_API_BASE_URL:-}" \
  -e POLRI_BWC_API_VERSION="${POLRI_BWC_API_VERSION:-}" \
  -e POLRI_BWC_ENABLE_NATIVE_PTT_AUDIO="${POLRI_BWC_ENABLE_NATIVE_PTT_AUDIO:-}" \
  -e POLRI_BWC_TIMEOUT_SECONDS="${POLRI_BWC_TIMEOUT_SECONDS:-}" \
  "${IMAGE_NAME}" \
  /bin/bash -lc '
    set -euo pipefail

    flutter pub get

    flutter build apk "$@" \
      ${POLRI_BWC_USE_MOCK:+--dart-define=POLRI_BWC_USE_MOCK=${POLRI_BWC_USE_MOCK}} \
      ${POLRI_BWC_API_BASE_URL:+--dart-define=POLRI_BWC_API_BASE_URL=${POLRI_BWC_API_BASE_URL}} \
      ${POLRI_BWC_API_VERSION:+--dart-define=POLRI_BWC_API_VERSION=${POLRI_BWC_API_VERSION}} \
      ${POLRI_BWC_ENABLE_NATIVE_PTT_AUDIO:+--dart-define=POLRI_BWC_ENABLE_NATIVE_PTT_AUDIO=${POLRI_BWC_ENABLE_NATIVE_PTT_AUDIO}} \
      ${POLRI_BWC_TIMEOUT_SECONDS:+--dart-define=POLRI_BWC_TIMEOUT_SECONDS=${POLRI_BWC_TIMEOUT_SECONDS}}

    cp build/app/outputs/flutter-apk/*.apk /out/
    ls -lh /out
  ' bash "${BUILD_ARGS[@]}"
