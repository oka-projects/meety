#!/bin/bash
# Monta o motor Python embutido do Meety em engine/dist/.
#
# O motor é um Python standalone (python-build-standalone, arm64) com mlx-whisper e mlx-lm
# instalados dentro dele. O app chama engine/dist/python/bin/python3 meety_engine.py <comando>.
# Nada de Homebrew, venv ou ffmpeg: o áudio chega já decodificado pelo AVFoundation.
#
# Uso: scripts/build-engine.sh [--sign "<identidade>"] [--release]
#   --sign     identidade de assinatura (padrão: Developer ID Application do chaveiro, ou "-" ad hoc)
#   --release  assina com runtime reforçado e carimbo de tempo (exigido pela notarização)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
ENGINE="$ROOT/engine"
# A pasta final chama-se "engine": é copiada inteira para Contents/Resources/engine.
DIST="$ENGINE/dist/engine"
CACHE="$ENGINE/.cache"

# Versão fixa do Python. Ao mudar, atualize também o checksum.
PBS_TAG="20261013"
PBS_FILE="cpython-3.12.15+${PBS_TAG}-aarch64-apple-darwin-install_only_stripped.tar.gz"
PBS_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_TAG}/${PBS_FILE}"
PBS_SHA256_FILE="$ENGINE/python-build-standalone.sha256"

SIGN_ID=""
RELEASE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign) SIGN_ID="$2"; shift 2 ;;
    --release) RELEASE=1; shift ;;
    *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
  [[ -z "$SIGN_ID" ]] && SIGN_ID="-"
fi

echo "==> Python ${PBS_FILE}"
mkdir -p "$CACHE"
if [[ ! -f "$CACHE/$PBS_FILE" ]]; then
  curl -L --fail -o "$CACHE/$PBS_FILE.part" "$PBS_URL"
  mv "$CACHE/$PBS_FILE.part" "$CACHE/$PBS_FILE"
fi
if [[ -f "$PBS_SHA256_FILE" ]]; then
  echo "$(cat "$PBS_SHA256_FILE")  $CACHE/$PBS_FILE" | shasum -a 256 -c -
else
  shasum -a 256 "$CACHE/$PBS_FILE" | cut -d' ' -f1 > "$PBS_SHA256_FILE"
  echo "checksum gravado em $PBS_SHA256_FILE (primeira vez)"
fi

echo "==> Extraindo"
rm -rf "$ENGINE/dist"
mkdir -p "$DIST"
tar -xzf "$CACHE/$PBS_FILE" -C "$DIST"   # cria $DIST/python
PY="$DIST/python/bin/python3.12"
"$PY" --version

echo "==> Pacotes"
# Sem dependências automáticas: o mlx-whisper declara torch (550 MB), que só serve para
# converter modelos. A lista completa e fixada está em requirements.lock.
"$PY" -m pip install --quiet --upgrade pip
if [[ -f "$ENGINE/requirements.lock" ]]; then
  "$PY" -m pip install --quiet --no-deps --no-compile -r "$ENGINE/requirements.lock"
else
  # Primeira vez: resolve a partir do requirements.in (mlx-whisper sem as suas dependências,
  # para o torch ficar de fora) e grava o lock.
  grep -E '^mlx-whisper==' "$ENGINE/requirements.in" | xargs "$PY" -m pip install --quiet --no-deps --no-compile
  grep -vE '^\s*(#|$|mlx-whisper==)' "$ENGINE/requirements.in" | xargs "$PY" -m pip install --quiet --no-compile
  "$PY" -m pip freeze --exclude pip | grep -v '^torch' > "$ENGINE/requirements.lock"
  echo "lock gravado em $ENGINE/requirements.lock"
fi
# Confere que nada ficou faltando (o aviso do torch é esperado).
"$PY" -m pip check | grep -v "mlx-whisper .* requires torch" || true
cp "$ENGINE/meety_engine.py" "$DIST/meety_engine.py"

echo "==> Enxugando"
SP="$DIST/python/lib/python3.12/site-packages"
# Coisas que o motor não usa e que só aumentam o app ou atrapalham a assinatura.
rm -rf "$DIST/python/include" "$DIST/python/share" \
       "$DIST/python/lib/python3.12/idlelib" "$DIST/python/lib/python3.12/tkinter" \
       "$DIST/python/lib/python3.12/turtledemo" "$DIST/python/lib/python3.12/test" \
       "$DIST/python/lib/python3.12/ensurepip" \
       "$SP/mlx/include" "$SP/mlx/lib/cmake" \
       "$SP/pip" "$SP"/pip-*.dist-info
find "$DIST/python" -name "__pycache__" -type d -prune -exec rm -rf {} +
# Só pastas "tests": "numpy/testing" e afins são usadas em tempo de execução (o scipy importa).
find "$SP" -type d -name tests -prune -exec rm -rf {} +
find "$DIST/python" -name "*.pyc" -delete
# Links simbólicos não entram num bundle assinado: trocamos por cópias.
find "$DIST/python" -type l | while read -r link; do
  target=$(readlink -f "$link"); rm "$link"; cp -R "$target" "$link"
done

echo "==> Assinando com: $SIGN_ID"
SIGN_ARGS=(--force --sign "$SIGN_ID")
if [[ $RELEASE -eq 1 ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
else
  SIGN_ARGS+=(--timestamp=none)
fi
ENT="$ENGINE/engine.entitlements"
# Cada Mach-O do motor é assinado individualmente: o Xcode não assina binários dentro de Resources,
# e a notarização recusa qualquer um que fique sem assinatura.
find "$DIST/python" -type f \( -name "*.so" -o -name "*.dylib" -o -perm +111 \) | while read -r f; do
  if file -b "$f" | grep -q "Mach-O"; then
    codesign "${SIGN_ARGS[@]}" --entitlements "$ENT" "$f" 2>&1 | grep -v "replacing existing signature" || true
  fi
done

echo "==> Conferindo"
"$PY" "$DIST/meety_engine.py" health
du -sh "$DIST"
echo "motor pronto em $DIST"
