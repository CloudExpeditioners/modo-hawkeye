#!/usr/bin/env bash
# Uso: publish-result.sh <archivo.json> <ruta_destino_en_rama>
# Publica el resultado en la rama `hawkeye-results`. Power Automate lo lee desde ahí
# (API de contenidos de GitHub) para devolverlo al agente. Es el "registro de auditoría" de Hawkeye.
set -euo pipefail

FILE="$1"; DEST="$2"; BRANCH="hawkeye-results"
WT="$(mktemp -d)"
REPO_DIR="$(pwd)"
cleanup() { cd "$REPO_DIR" && git worktree remove --force "$WT" >/dev/null 2>&1 || true; }
trap cleanup EXIT

git config --global user.name  "hawkeye-bot"
git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"

if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  git fetch --depth=1 origin "$BRANCH"
  git worktree add --detach "$WT" FETCH_HEAD
else
  git worktree add --detach "$WT"
  ( cd "$WT" && git checkout -q --orphan "hawkeye-results-tmp-$$" && git rm -rfq . )
  printf '# hawkeye-results\nRegistro de auditoría generado por Modo Hawkeye. No editar a mano.\n' > "$WT/README.md"
  ( cd "$WT" && git add README.md )
fi

mkdir -p "$WT/$(dirname "$DEST")"
cp "$FILE" "$WT/$DEST"

cd "$WT"
git add "$DEST"
git commit -qm "hawkeye: $(basename "$DEST" .json)"

for attempt in 1 2 3 4; do
  if git push -q origin "HEAD:$BRANCH"; then
    echo "Publicado: $BRANCH/$DEST"
    exit 0
  fi
  echo "Push rechazado (intento $attempt), rebase y reintento..."
  sleep $((attempt * 2))
  git pull -q --rebase origin "$BRANCH" || true
done

echo "::error::No se pudo publicar el resultado en $BRANCH"
exit 1
