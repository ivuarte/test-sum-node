#!/usr/bin/env bash
# copy_and_rotate_logs.sh
# Copia carpetas de logs desde un workspace origen a un repo destino (save_log),
# crea un snapshot con timestamp y rota manteniendo solo los 5 más recientes.

set -Eeuo pipefail

log()  { echo "[$(date '+%F %T')] $*"; }
fail() { echo "[$(date '+%F %T')] ERROR: $*" >&2; exit 1; }

# --------- Parámetros esperados (por env) ----------
: "${TARGET_REPO_URL:?Falta TARGET_REPO_URL (ej: https://github.com/ivuarte/save_log.git)}"
: "${GITHUB_TOKEN:?Falta GITHUB_TOKEN (PAT con permiso repo:push)}"
: "${CLIENTE:?Falta CLIENTE (identificador de cliente)}"

SOURCE_ROOT="${SOURCE_ROOT:-$WORKSPACE}"                 # carpeta origen (repo que clonó el freestyle)
TARGET_BRANCH="${TARGET_BRANCH:-main}"                   # rama a usar en save_log
SRC_DIRS="${SRC_DIRS:-webapp/test jenkins-tests/test}"   # rutas relativas a SOURCE_ROOT
CLONE_DIR="${CLONE_DIR:-$WORKSPACE/_save_log}"           # dónde clonar save_log
GITHUB_USER="${GITHUB_USER:-ivuarte}"                    # usuario para el push

timestamp="$(date +%Y%m%d-%H%M%S)"
GIT_SHA="${GIT_COMMIT:-$(cd "$SOURCE_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')}"

# --------- Clonar repo destino ----------
rm -rf "$CLONE_DIR"
mkdir -p "$CLONE_DIR"
# No mostramos el token en logs
REMOTE_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@${TARGET_REPO_URL#https://}"

log "Clonando repo destino..."
git clone "$REMOTE_URL" "$CLONE_DIR"
cd "$CLONE_DIR"
git config user.name "${GIT_AUTHOR_NAME:-Jenkins Bot}"
git config user.email "${GIT_AUTHOR_EMAIL:-jenkins@example.local}"
git checkout -B "$TARGET_BRANCH"

# Estructura destino: logs/<cliente>/<timestamp>/
dest="logs/${CLIENTE}/${timestamp}"
mkdir -p "$dest"

# --------- Copia de carpetas ----------
copied_any=0
for rel in $SRC_DIRS; do
  src="${SOURCE_ROOT%/}/$rel"
  if [[ -d "$src" ]]; then
    log "Copiando $src -> $dest/$rel"
    mkdir -p "$dest/$(dirname "$rel")"
    # copia preservando atributos; contenido de src dentro de la ruta destino
    cp -a "${src}/." "$dest/$rel/"
    copied_any=1
  else
    log "Omitido (no existe): $src"
  fi
done

if [[ "$copied_any" -eq 0 ]]; then
  fail "No se encontró ninguna carpeta de origen para copiar. Abortando."
fi

# Metadatos del snapshot
{
  echo "cliente=$CLIENTE"
  echo "source_commit=$GIT_SHA"
  echo "created_at=$(date --iso-8601=seconds)"
} > "$dest/.meta"

# --------- Commit de agregado ----------
git add -A
if git commit -m "Add logs for ${CLIENTE} - ${timestamp} (source ${GIT_SHA})"; then
  log "Commit de agregado OK"
else
  log "Nada que commitear en el agregado"
fi

# --------- Rotación (mantener solo 5 más recientes) ----------
log "Rotando snapshots (mantener 5 más recientes)…"
cd "logs/${CLIENTE}"
mapfile -t snapshots < <(ls -1 | sort)  # orden ascendente (timestamp lexicográfico)
count=${#snapshots[@]}
to_delete=$(( count>5 ? count-5 : 0 ))
if (( to_delete > 0 )); then
  for ((i=0; i<to_delete; i++)); do
    old="${snapshots[$i]}"
    log "Eliminando snapshot antiguo: $old"
    rm -rf -- "$old"
  done
  cd "$CLONE_DIR"
  git add -A
  git commit -m "Clean old logs for ${CLIENTE} (removed ${to_delete} snapshot/s)"
else
  log "No hay snapshots que eliminar (<=5 presentes)."
  cd "$CLONE_DIR"
fi

# --------- Push ----------
log "Haciendo push a ${TARGET_BRANCH}…"
git push origin "$TARGET_BRANCH"
log "Listo. Snapshot en: ${dest}"
