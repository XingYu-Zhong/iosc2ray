#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.build/libxray-src"
OUTPUT_DIR="${ROOT_DIR}/Vendor"

if ! command -v git >/dev/null 2>&1; then
  echo "git not found" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found" >&2
  exit 1
fi
if ! command -v go >/dev/null 2>&1; then
  echo "go not found" >&2
  exit 1
fi

mkdir -p "${ROOT_DIR}/.build" "${OUTPUT_DIR}"

if [ ! -d "${WORK_DIR}" ]; then
  git clone --depth=1 https://github.com/XTLS/libXray.git "${WORK_DIR}"
else
  git -C "${WORK_DIR}" pull --ff-only
fi

pushd "${WORK_DIR}" >/dev/null
python3 build/main.py apple go
popd >/dev/null

rm -rf "${OUTPUT_DIR}/LibXray.xcframework"
cp -R "${WORK_DIR}/LibXray.xcframework" "${OUTPUT_DIR}/LibXray.xcframework"

echo "LibXray.xcframework prepared at: ${OUTPUT_DIR}/LibXray.xcframework"
