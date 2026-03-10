#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: collect_package_files.sh <image_ref> <trivy_report.json> <output_tsv>" >&2
  exit 1
fi

IMAGE_REF="$1"
REPORT_PATH="$2"
OUTPUT_PATH="$3"
WORK_DIR="$(mktemp -d)"
PKG_LIST="$WORK_DIR/vulnerable-packages.txt"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

jq -r '[.Results[]?.Vulnerabilities[]?.PkgName] | unique | map(select(length > 0)) | .[]' "$REPORT_PATH" > "$PKG_LIST"

if [ ! -s "$PKG_LIST" ]; then
  : > "$OUTPUT_PATH"
  exit 0
fi

docker run --rm \
  -v "$WORK_DIR:/workspace:ro" \
  --entrypoint /bin/sh \
  "$IMAGE_REF" \
  -eu -c '
    if command -v dpkg-query >/dev/null 2>&1; then
      while IFS= read -r pkg; do
        dpkg-query -L "$pkg" 2>/dev/null | awk -v pkg="$pkg" '"'"'NF && $0 ~ "^/" {print pkg "\t" $0}'"'"' || true
      done < /workspace/vulnerable-packages.txt
    elif command -v apk >/dev/null 2>&1; then
      while IFS= read -r pkg; do
        apk info -L "$pkg" 2>/dev/null | awk -v pkg="$pkg" '"'"'NF && $0 ~ "^/" {print pkg "\t" $0}'"'"' || true
      done < /workspace/vulnerable-packages.txt
    elif command -v rpm >/dev/null 2>&1; then
      while IFS= read -r pkg; do
        rpm -ql "$pkg" 2>/dev/null | awk -v pkg="$pkg" '"'"'NF && $0 ~ "^/" {print pkg "\t" $0}'"'"' || true
      done < /workspace/vulnerable-packages.txt
    else
      echo "Unsupported package manager in image $IMAGE_REF" >&2
      exit 1
    fi
  ' | sort -u > "$OUTPUT_PATH"
