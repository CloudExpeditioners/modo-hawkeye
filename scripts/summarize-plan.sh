#!/usr/bin/env bash
# Uso: summarize-plan.sh <plan.json> <out_dir>
# Genera: changes.json (resumen seguro), changes.md (legible) y fingerprint.txt (huella del plan)
set -euo pipefail

PLAN_JSON="$1"
OUT_DIR="${2:-.}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT_DIR"

jq -f "$HERE/summarize-plan.jq" "$PLAN_JSON" > "$OUT_DIR/changes.json"

# La huella identifica EXACTAMENTE qué se va a cambiar. Si el estado de Azure cambia
# entre el diagnóstico y la aprobación, la huella cambia y la corrección se bloquea.
jq -cS '.' "$OUT_DIR/changes.json" | sha256sum | cut -d' ' -f1 > "$OUT_DIR/fingerprint.txt"

jq -r -f "$HERE/render-changes.jq" "$OUT_DIR/changes.json" > "$OUT_DIR/changes.md"

echo "Cambios: $(jq 'length' "$OUT_DIR/changes.json") · huella: $(cut -c1-12 "$OUT_DIR/fingerprint.txt")"
